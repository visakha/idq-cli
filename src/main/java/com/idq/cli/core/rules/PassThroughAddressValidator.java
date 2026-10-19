package com.idq.cli.core.rules;

import static com.idq.cli.core.Infa.substr;
import static com.idq.cli.core.Infa.trim;
import static com.idq.cli.core.Infa.upper;

import com.idq.cli.core.reference.ReferenceData;
import java.math.BigDecimal;
import org.springframework.stereotype.Component;

/// [AddressValidator] without AddressDoctor: all mapplet expressions run, the service itself echoes its input.
///
/// AddressDoctor-only attributes (match code, mailability score, geocodes, CASS) are `NULL`; latitude and longitude
/// default to 0 as `exp_Latt_Lngtd_Dec_Conv` does for empty geocodes. A `NULL` mailability score scores as a good
/// address in [AddressRules#score].
@Component
public class PassThroughAddressValidator implements AddressValidator {

    @Override
    public Result validate(Input in, ReferenceData reference) {
        var srcSys = in.srcSys() == null ? "TRS" : in.srcSys();
        var line1 = AddressRules.postScrub(AddressRules.preScrub(AddressRules.stripSuite(in.address1()), false));
        var line2 = AddressRules.postScrub(AddressRules.preScrub(AddressRules.stripSuite(in.address2()), true));
        var state = upper(trim(in.state()));
        var sourceState = state == null ? null : reference.masterCode("STATE", srcSys, state).orElse(null);
        var postcode = trim(in.postalCode());
        var zip5 = substr(postcode, 1, 5);
        var stateFips = AddressRules.stateFips(null, sourceState, zip5);
        return new Result(line1, line2, in.city(), postcode, zip5, substr(postcode, 7, 4), in.country(), null,
                stateFips, AddressRules.countyFips(null, null), BigDecimal.ZERO, BigDecimal.ZERO, null, null, null,
                null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null);
    }
}
