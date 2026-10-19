package com.idq.cli.core.rules;

import com.idq.cli.core.reference.ReferenceData;
import java.math.BigDecimal;

/// `mplt_Global_Addr_Validation`: the Informatica AddressDoctor hybrid validation
/// (`dq_Global_AddressValidation_Hybrid`) wrapped by preparation and scrub expressions.
/// See `docs/mappings/000_mapplets.md#address-validation`.
///
/// AddressDoctor is a licensed external service; [PassThroughAddressValidator] implements every expression around
/// it and echoes the prepared input in place of the service result. Plug a real implementation in as a bean.
public interface AddressValidator {

    Result validate(Input input, ReferenceData reference);

    record Input(String address1, String address2, String city, String state, String postalCode, String country,
            String srcSys) {}

    /// Mapplet output ports used by the mappings (AddressDoctor names).
    record Result(
            String deliveryAddressLine1, String deliveryAddressLine2, String city, String postcodeComplete,
            String zip5, String zip4, String countryIso2, String provinceIso3, String stateFips, String countyFips,
            BigDecimal latitude, BigDecimal longitude, String matchCode, String matchCodeDescription,
            String mailabilityScore, String addressType, String buildingName, String buildingNumber,
            String buildingComplete, String subBuildingNumber, String subBuildingComplete,
            String subBuildingDescriptor, String organizationName, String organizationDescriptor,
            String organizationDepartment, String geocodingStatus, String residentialDeliveryIndicator,
            String resultPercentage, String earlyWarningCode, String cassErrorCode, String deliveryPointValidation) {}
}
