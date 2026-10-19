package com.idq.cli.core;

import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.target.TargetBatch;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/// The `STG_<SRC>_PTY_INACTIVE_STS` / `_LOG` pattern of the ECI, FSS, TTF and WIC workflows.
///
/// The `*_Pty_Validation` mapping decides which parties are deactivated or reactivated; every later mapping of the
/// workflow drops rows whose party key has a deactivation status.
public final class InactiveStatus {

    private InactiveStatus() {}

    /// Current deactivation status per party source key (`SRC_KEY`) for one `ROWID_SYSTEM`.
    public record Lookup(Map<String, String> statusBySrcKey) {
        public static final Lookup NONE = new Lookup(Map.of());

        public Optional<String> status(String srcKey) {
            return Optional.ofNullable(statusBySrcKey.get(srcKey));
        }

        /// The `Flt_Remove_Inactive` / `fil_deactivated_status` filter: `ISNULL(DEACTIVATION_STS)`.
        public boolean isActive(String srcKey) {
            return srcKey == null || !statusBySrcKey.containsKey(srcKey);
        }
    }

    public record Status(String srcKey, String rowidSystem, String deactivationSts, LocalDateTime deactivationDt) {}

    public record Log(String srcKey, String rowidSystem, String action, LocalDateTime actionDt) {}

    /// `H` history (no hub cross-reference), `D` already deactivated in the hub (`HUB_STATE_IND = -1`), otherwise
    /// `P` pending deactivation.
    public static String newDeactivationStatus(Integer hubStateInd) {
        return hubStateInd == null ? "H" : hubStateInd == -1 ? "D" : "P";
    }

    /// Constructor of a source-specific `STG_<SRC>_PTY_INACTIVE_STS` or `_LOG` entity.
    @FunctionalInterface
    public interface RowFactory<T> {
        T create(String srcKey, String rowidSystem, String statusOrAction, LocalDateTime when);
    }

    /// Log rows appended, reactivated statuses deleted by key, new statuses appended - then the exception rows.
    public static <S, L> MappingOutput output(Changes changes, List<BadRecord> bad, Class<S> statusType,
            RowFactory<S> status, Class<L> logType, RowFactory<L> log) {
        var removed = new LinkedHashMap<S, Map<String, Object>>();
        changes.removedStatuses.forEach(s -> removed.put(status.create(s.srcKey(), s.rowidSystem(), null, null),
                Map.of("SRC_KEY", s.srcKey(), "ROWID_SYSTEM", s.rowidSystem())));
        return MappingOutput.empty()
                .load(TargetBatch.append(logType, changes.logs.stream()
                        .map(l -> log.create(l.srcKey(), l.rowidSystem(), l.action(), l.actionDt())).toList()))
                .load(TargetBatch.deleteByKey(statusType, List.copyOf(removed.keySet()), removed::get))
                .load(TargetBatch.append(statusType, changes.newStatuses.stream()
                        .map(s -> status.create(s.srcKey(), s.rowidSystem(), s.deactivationSts(), s.deactivationDt()))
                        .toList()))
                .reject(bad);
    }

    /// Accumulates the effect of the validation router.
    public static final class Changes {
        public final List<Log> logs = new ArrayList<>();
        public final List<Status> newStatuses = new ArrayList<>();
        public final List<Status> removedStatuses = new ArrayList<>();
        private final String rowidSystem;
        private final LocalDateTime now;

        public Changes(String rowidSystem, LocalDateTime now) {
            this.rowidSystem = rowidSystem;
            this.now = now;
        }

        /// Logs the deactivation and, when the party has no status yet, records a new one.
        public void deactivate(String srcKey, Integer hubStateInd, Optional<String> currentStatus) {
            logs.add(new Log(srcKey, rowidSystem, "Deactivation", now));
            if (currentStatus.isEmpty()) {
                newStatuses.add(new Status(srcKey, rowidSystem, newDeactivationStatus(hubStateInd), now));
            }
        }

        /// Logs the reactivation and deletes the party's status row.
        public void reactivate(String srcKey) {
            logs.add(new Log(srcKey, rowidSystem, "Reactivation", now));
            removedStatuses.add(new Status(srcKey, rowidSystem, null, null));
        }
    }
}
