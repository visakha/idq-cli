package com.idq.cli.core.rules;

import static com.idq.cli.core.Infa.in;
import static com.idq.cli.core.Infa.isNumber;
import static com.idq.cli.core.Infa.lower;
import static com.idq.cli.core.Infa.substr;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.reference.ReferenceData.AreaCode;
import com.idq.cli.core.rules.PersonRules.Checked;

/// Phone and e-mail rules. See `docs/mappings/000_mapplets.md#contact-rules`.
///
/// * [#email] - `rule_email_validation_v01` with its local-part and domain sub-rules
/// * [#phone] - `rule_Phone_Std`
/// * [#phoneExtension] - `rule_Phone_Extension_Std`
public final class ContactRules {

    /// Characters removed by the `std_to_number` token standardiser (space and tab included).
    private static final String PHONE_JUNK = "~`!@#$%^&*()_-+=}{[]|\\\"':;?/>.<, \t";

    private ContactRules() {}

    /// Lower-cases and trims the address; flags `Invalid_Email` when it contains white space, has no `@` or no dot
    /// after the `@`, or the domain / top-level domain breaks the domain rules.
    public static Checked<String> email(String email, EtlContext ctx) {
        var normalized = lower(trim(email));
        boolean whiteSpace = trim(email) != null && trim(email).matches(".*\\s+.*");
        int at = email == null ? -1 : email.indexOf('@');
        boolean badFormat = at < 0 || email.indexOf('.', at) < 0;
        boolean invalid = whiteSpace || "invalid".equals(normalized) || badFormat || !domainValid(normalized)
                || !topLevelDomainValid(normalized);
        return new Checked<>(normalized, invalid ? ctx.exception("Invalid_Email") : ExceptionInfo.NONE);
    }

    static String rootDomain(String email) {
        return email == null ? "" : trim(lower(email.substring(email.indexOf('@') + 1)));
    }

    static boolean domainValid(String email) {
        var root = rootDomain(email);
        int lastDot = root.lastIndexOf('.');
        var domain = lastDot < 0 ? "" : root.substring(0, lastDot);
        boolean firstLast = domain.indexOf('_') >= 1 || domain.startsWith(".") || domain.startsWith("-")
                || domain.endsWith("-");
        return !firstLast && domain.matches("[a-z0-9.-]+") && domain.indexOf("..") < 1 && root.indexOf("..") < 1;
    }

    static boolean topLevelDomainValid(String email) {
        var root = rootDomain(email);
        var tld = root.indexOf('.') < 0 ? "" : root.substring(root.lastIndexOf('.') + 1);
        return tld.matches("[a-z0-9]+") && tld.length() >= 2 && tld.length() <= 11;
    }

    /// Strips punctuation and white space, then validates a ten digit North American number against
    /// `REF_PHN_AREA_CD`. ECI numbers padded with `000` get `Missing_AreaCode`; main and other numbers of TRS, CRE
    /// and ECI may not use a toll-free area code.
    public static Checked<String> phone(String phone, String srcSys, String usageType, EtlContext ctx) {
        var digits = stripJunk(phone);
        var areaCode = substr(digits, 1, 3);
        AreaCode area = areaCode == null ? null : ctx.reference().areaCode(areaCode).orElse(null);
        String code;
        if (!isNumber(digits) || digits.length() != 10 || digits.equals("0000000000")
                || in(substr(digits, 4, 1), "0", "1")) {
            code = "Invalid_Phone_Number";
        } else if (in(srcSys, "ECI") && "000".equals(areaCode)) {
            code = "Missing_AreaCode";
        } else if (area == null || in(substr(digits, 1, 1), "0", "1")) {
            code = "Invalid_Phone_Number";
        } else if (in(srcSys, "TRS", "CRE", "ECI") && in(usageType, "001", "003")
                && "Toll-Free".equals(area.service())) {
            code = "Invalid_Phone_Number";
        } else {
            code = null;
        }
        return new Checked<>(digits, ctx.exception(code));
    }

    /// An extension must be 2 to 6 digits once special characters are removed; a missing extension is accepted.
    public static Checked<String> phoneExtension(String extension, EtlContext ctx) {
        var clean = SpecialCharacters.remove(extension);
        boolean invalid = clean != null && (clean.length() < 2 || clean.length() > 6 || !isNumber(clean));
        return new Checked<>(clean, invalid ? ctx.exception("Invalid_Phone_Number_Ext") : ExceptionInfo.NONE);
    }

    static String stripJunk(String phone) {
        if (phone == null) {
            return null;
        }
        return phone.chars().filter(c -> PHONE_JUNK.indexOf(c) < 0)
                .collect(StringBuilder::new, StringBuilder::appendCodePoint, StringBuilder::append).toString();
    }
}
