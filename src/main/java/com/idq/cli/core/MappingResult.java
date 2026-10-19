package com.idq.cli.core;

import java.time.Duration;
import java.util.Map;

/// Outcome of one mapping run.
public record MappingResult(String mapping, Status status, int rowsRead, Map<String, Integer> rowsWritten,
        int badRecords, Duration elapsed, String message) {

    public enum Status { SUCCEEDED, FAILED, SKIPPED }

    public static MappingResult failed(String mapping, Duration elapsed, Throwable error) {
        return new MappingResult(mapping, Status.FAILED, 0, Map.of(), 0, elapsed,
                error.getClass().getSimpleName() + ": " + error.getMessage());
    }

    public String summary() {
        return "%-48s %-9s read=%-6d written=%s exceptions=%d (%d ms)%s".formatted(mapping, status, rowsRead,
                rowsWritten, badRecords, elapsed.toMillis(), message == null ? "" : " " + message);
    }
}
