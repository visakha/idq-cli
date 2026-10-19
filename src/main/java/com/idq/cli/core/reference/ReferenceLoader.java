package com.idq.cli.core.reference;

import org.springframework.stereotype.Component;

/// Loads all shared lookup tables once per workflow run (IDQ builds its lookup caches per mapping run; the content
/// does not change during a workflow, so one snapshot is equivalent).
@Component
public class ReferenceLoader {

    private final ReferenceQueries queries;

    public ReferenceLoader(ReferenceQueries queries) {
        this.queries = queries;
    }

    public ReferenceSnapshot load() {
        var snapshot = ReferenceSnapshot.empty();
        queries.lookupCodeValues().forEach(r -> snapshot.withCodeValue(r.codeType(), r.srcSys(), r.srcCodeValue(),
                r.mstrRefCode(), r.mstrRefLabel()));
        queries.viewCodeValues().forEach(r -> snapshot.withMasterCode(r.codeType(), r.srcSys(), r.srcCodeValue(),
                r.mstrCodeValue()));
        queries.exceptionCodes().forEach(r -> snapshot.withException(r.exceptionCode(), r.exceptionDesc(),
                r.exceptionType()));
        queries.areaCodes().forEach(r -> snapshot.withAreaCode(r.npaId(), r.service()));
        queries.junkNames().forEach(r -> snapshot.withJunkName(r.name(), r.editLimitation()));
        queries.streetTypes().forEach(r -> snapshot.withStreetType(r.code(), r.description()));
        return snapshot;
    }
}
