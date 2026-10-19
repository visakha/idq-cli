package com.idq.cli.core.rules;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.rules.PersonRules.Checked;

/// Alternate identifier rules. See `docs/mappings/000_mapplets.md#identifier-rules`.
///
/// * [#ssnIsValid] - `rule_USA_SSN_Validation_post_June2011`
/// * [#medicaidId] - `rule_MEDICAID_ID_Std`
/// * [#memberId] - `rule_Member_Id_Std`
public final class IdentifierRules {

    private IdentifierRules() {}

    /// The IDQ rule labels the value with the `USANATID1` token set (randomised SSNs issued after June 2011):
    /// nine digits, optionally dash or space separated, area not `000`, `666` or `9xx`, group not `00`, serial not
    /// `0000`.
    public static boolean ssnIsValid(String ssn) {
        if (ssn == null) {
            return false;
        }
        var digits = ssn.strip().replace("-", "").replace(" ", "");
        if (!digits.matches("\\d{9}")) {
            return false;
        }
        var area = digits.substring(0, 3);
        return !area.equals("000") && !area.equals("666") && area.charAt(0) != '9'
                && !digits.substring(3, 5).equals("00") && !digits.substring(5).equals("0000");
    }

    /// `exp_validate_ssn`: an invalid SSN is blanked and raises `Invalid_SSN`.
    public static Checked<String> ssn(String ssn, EtlContext ctx) {
        return ssnIsValid(ssn) ? new Checked<>(ssn, ExceptionInfo.NONE)
                : new Checked<>(null, ctx.exception("Invalid_SSN"));
    }

    /// Special characters removed; anything but nine characters raises `Invalid_Medicaid_Id`.
    public static Checked<String> medicaidId(String medicaidId, EtlContext ctx) {
        var clean = SpecialCharacters.remove(medicaidId);
        boolean invalid = clean != null && clean.length() != 9;
        return new Checked<>(clean, invalid ? ctx.exception("Invalid_Medicaid_Id") : ExceptionInfo.NONE);
    }

    /// Special characters removed; anything but nine or ten characters raises `Invalid_Member_Id`.
    public static Checked<String> memberId(String memberId, EtlContext ctx) {
        var clean = SpecialCharacters.remove(memberId);
        boolean invalid = clean != null && clean.length() != 9 && clean.length() != 10;
        return new Checked<>(clean, invalid ? ctx.exception("Invalid_Member_Id") : ExceptionInfo.NONE);
    }
}
