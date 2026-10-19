package com.idq.cli.core;

import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.rules.AddressValidator;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.DqmAddress;
import com.idq.cli.core.rules.AddressRules;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.RowFactory;
import com.idq.cli.core.target.StagingRow;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.time.LocalDateTime;

/// Address-mapping patterns shared by TRS, ECI, FSS and WIC: the `DQM_ADDRESS` audit row, the `Invalid_Address`
/// exception row and the validated column group of `C_S_*_PTY_RLE_ADDR`.
public final class AddressPatterns {

    private AddressPatterns() {}

    public static Columns.ValidatedAddress validated(AddressValidator.Result av, String line1, String line2) {
        return new Columns.ValidatedAddress(line1, line2, av.buildingName(), av.subBuildingNumber(), av.city(),
                av.countyFips(), av.stateFips(), av.countryIso2(), av.zip5(), av.zip4(), av.latitude(),
                av.longitude(), av.matchCode(), av.mailabilityScore(), av.addressType(), av.organizationDescriptor(),
                av.organizationName(), av.buildingNumber(), av.subBuildingComplete(), av.subBuildingDescriptor(),
                av.geocodingStatus(), av.residentialDeliveryIndicator());
    }

    public static DqmAddress dqm(String ptySrcKey, String addrSrcKey, String srcSystem, String mdmAddrTp,
            LocalDateTime loadDt, Columns.SourceAddress src, String srcPostal, AddressValidator.Result av) {
        return new DqmAddress(ptySrcKey, addrSrcKey, srcSystem, mdmAddrTp, loadDt, src.srcAddrLn1(),
                src.srcAddrLn2(), src.srcCity(), src.srcState(), srcPostal, src.srcCntry(), src.srcCounty(),
                av.deliveryAddressLine1(), av.deliveryAddressLine2(), av.city(), av.stateFips(), av.postcodeComplete(),
                av.countryIso2(), av.countyFips(), av.countyFips(), av.stateFips(), av.latitude(), av.longitude(),
                av.geocodingStatus(), av.residentialDeliveryIndicator(), av.organizationDescriptor(),
                av.organizationDepartment(), av.organizationName(), av.buildingComplete(), av.subBuildingComplete(),
                av.mailabilityScore(), av.matchCode(), decimal(av.resultPercentage()), av.addressType(),
                av.earlyWarningCode(), av.cassErrorCode(), av.deliveryPointValidation());
    }

    /// `Invalid_Address` row carrying the source address and the AddressDoctor verdict.
    public static BadRecord badData4Address(EtlContext ctx, ExceptionInfo exception, String sourceAddressType,
            Columns.SourceAddress src, String matchCode, String matchDescription, String mailabilityScore,
            LocalDateTime periodStart, LocalDateTime periodEnd, Object id1, Object id2, Object id3) {
        return ctx.badRecord().ids(id1, id2, id3).exception(exception)
                .attribute("Address", AddressRules.describe(src.srcAddrLn1(),
                        src.srcAddrLn2(), src.srcCity(), src.srcState(), src.srcPstlCd(), src.srcPstlCdExt(),
                        src.srcCntry()))
                .address(sourceAddressType, src.srcAddrLn1(), src.srcAddrLn2(), src.srcCity(), src.srcCounty(),
                        src.srcState(), src.srcPstlCd(), src.srcPstlCdExt(), src.srcCntry())
                .addressDoctor(matchCode, matchDescription, mailabilityScore).period(periodStart, periodEnd).build();
    }

    /// One source address of the ECI / FSS / WIC address mappings, keys already formulated.
    public record Candidate(String ptySrcKey, String pkey, String ptyRleFk, String addrTypeMaster,
            String sourceAddrType, Columns.SourceAddress source, String validationPostalCode, String locIdn,
            LocalDateTime periodStart, LocalDateTime effBegin, LocalDateTime sourceLastUpdate, Object id1, Object id2,
            Object id3) {}

    public record Routed<R>(List<DqmAddress> dqm, List<R> addresses, List<BadRecord> exceptions) {}

    /// `Invalid Address per Address Doctor`, as hard-coded by the ECI, FSS and WIC mappings.
    public static final ExceptionInfo INVALID_ADDRESS = new ExceptionInfo("Invalid_Address",
            "Invalid Address per Address Doctor", "Bad Value");

    /// Validate, audit to `DQM_ADDRESS`, score, then load good addresses and queue the others.
    public static <R extends StagingRow<Columns.Address>> Routed<R> route(List<Candidate> candidates,
            AddressValidator validator, EtlContext ctx, RowFactory<Columns.Address, R> factory) {
        var dqm = new ArrayList<DqmAddress>();
        var addresses = new ArrayList<R>();
        var bad = new ArrayList<BadRecord>();
        for (var c : candidates) {
            var src = c.source();
            var av = validator.validate(new AddressValidator.Input(src.srcAddrLn1(), src.srcAddrLn2(), src.srcCity(),
                    src.srcState(), c.validationPostalCode(), src.srcCntry(), ctx.sourceSystem()), ctx.reference());
            dqm.add(dqm(c.ptySrcKey(), c.pkey(), ctx.sourceSystem(), c.addrTypeMaster(), ctx.runStart(), src,
                    src.srcPstlCd(), av));
            if (AddressRules.score(c.addrTypeMaster(), av.mailabilityScore(), av.matchCode())
                    == AddressRules.Score.EXCEPTION) {
                bad.add(badData4Address(ctx, INVALID_ADDRESS, c.sourceAddrType(), src, av.matchCode(),
                        av.matchCodeDescription(), av.mailabilityScore(), c.effBegin(), null, c.id1(), c.id2(),
                        c.id3()));
                continue;
            }
            var lines = AddressRules.holdLines(av.deliveryAddressLine1(), av.deliveryAddressLine2());
            var audit = MdmAudit.srcRowid(c.pkey()).periodStart(c.periodStart()).lastUpdated(ctx.runStart())
                    .created(c.sourceLastUpdate()).by(null, ctx.mappingName()).hubState(1)
                    .sourceUpdated(c.sourceLastUpdate());
            addresses.add(factory.create(c.pkey(), audit, new Columns.Address(c.ptyRleFk(), c.addrTypeMaster(),
                    "Primary", "Member", "Member Addr", c.locIdn(), validated(av, lines.line1(), lines.line2()), src,
                    c.effBegin(), null)));
        }
        return new Routed<>(dqm, addresses, bad);
    }

    public static BigDecimal decimal(String value) {
        return Infa.isNumber(value) ? new BigDecimal(value.strip()) : null;
    }
}
