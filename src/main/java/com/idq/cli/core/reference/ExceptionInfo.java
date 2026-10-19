package com.idq.cli.core.reference;

/// An exception code with the description and type configured in `EXC_LOOKUP_CODE_VALUE`.
public record ExceptionInfo(String code, String description, String type) {

    public static final ExceptionInfo NONE = new ExceptionInfo(null, null, null);

    /// The IDQ lookup `EXCEPTION_CODE = :code`; unknown codes keep the code with empty description and type.
    public static ExceptionInfo of(String code, ReferenceData reference) {
        return code == null ? NONE : reference.exception(code);
    }

    public boolean present() {
        return code != null;
    }

    /// The lookup found the code in `EXC_LOOKUP_CODE_VALUE`; IDQ routers that test the looked-up description or
    /// code only fire in that case.
    public boolean configured() {
        return description != null || type != null;
    }
}
