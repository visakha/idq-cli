package com.idq.cli.source.cre.etlmap.svc;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.EtlPatterns.write2TargetPhone;
import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.hasText;
import static com.idq.cli.core.Infa.in;
import static com.idq.cli.core.Infa.initcap;
import static com.idq.cli.core.Infa.isMissing;
import static com.idq.cli.core.Infa.nvl;
import static com.idq.cli.core.Infa.pipe;
import static com.idq.cli.core.Infa.substr;

import com.idq.cli.core.EtlContext;
import com.idq.cli.core.EtlPatterns;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.exception.BadRecords;
import com.idq.cli.core.reference.ExceptionInfo;
import com.idq.cli.core.reference.MdmBaseTables;
import com.idq.cli.core.rules.AddressValidator;
import com.idq.cli.core.rules.ContactRules;
import com.idq.cli.core.rules.IdentifierRules;
import com.idq.cli.core.rules.NameStandardization;
import com.idq.cli.core.rules.PersonRules;
import com.idq.cli.core.rules.SpecialCharacters;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.mdmdc.etldb.models.CreTargets;
import com.idq.cli.mdmdc.etldb.repo.CreAddressRepository;
import com.idq.cli.mdmdc.etldb.repo.CreAlternateIdRepository;
import com.idq.cli.mdmdc.etldb.repo.CrePartyRepository;
import com.idq.cli.mdmdc.etldb.repo.CrePartyRoleRepository;
import com.idq.cli.mdmdc.etldb.repo.CrePhoneRepository;
import com.idq.cli.source.cre.etldb.models.CreQueryRows.CareClient;
import com.idq.cli.source.cre.etldb.models.CreQueryRows.PartyXref;
import com.idq.cli.source.cre.etldb.models.CreSources;
import com.idq.cli.source.cre.etldb.repo.CreCareClientsDeltaRepository;
import com.idq.cli.source.cre.etldb.repo.CrePartyHmrgRepository;
import com.idq.cli.source.cre.etldb.repo.CrePartyXrefRepository;
import com.idq.cli.source.cre.etldb.repo.CreSourceMergeRepository;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_CRE_CARE_Clients` - the whole CRE workflow in one mapping: case moves for MDM to merge, then
/// demographics, member role, address, phone and alternate ids of every valid CARE client.
/// See [docs/mappings/034_m_Tgt_C_S_CRE_CARE_Clients.md].
@Service
public class CreCareClientsService {

    public static final MappingInfo INFO = MappingInfo.of("034", "m_Tgt_C_S_CRE_CARE_Clients", SourceSystem.CRE,
            List.of(CreTargets.Party.class, CreTargets.PartyRole.class, CreTargets.Address.class,
                    CreTargets.Phone.class, CreTargets.AlternateId.class, CreSources.SourceMerge.class),
            List.of(CreSources.CareClientsDelta.class, CreSources.CareClients.class,
                    CreSources.CareCaseMaintDelta.class, MdmBaseTables.PartyXref.class,
                    MdmBaseTables.PartyHmrg.class));

    static final String SRC = "CRE";
    /// `$PHYSICAL_ADDR_TYPE_CD`
    public static final String ADDRESS_TYPE = "002";
    /// `$Default_NonUS_State_CD`, also the literal the `RTR_US_ADDRESSES` condition tests.
    static final String NON_US_STATE = "99";

    /// @param crossReferences `C_B_PTY_XREF` of `ROWID_SYSTEM` CRE by `PKEY_SRC_OBJECT` (any row)
    /// @param mergedSources   `C_B_PTY_HMRG.SRC_ROWID_OBJECT` of every merge
    /// @param mergedTargets   `C_B_PTY_HMRG.TGT_ROWID_OBJECT` of every merge
    public record Lookups(Map<String, PartyXref> crossReferences, Set<String> mergedSources,
            Set<String> mergedTargets) {}

    /// One `Union` row after `mplt_Name_Standardization_Indv_Member`.
    ///
    /// @param mergeResult `ORIG_ROWID_OBJECT_DESC`: `N` when MDM has no merge history for the case move yet, `Y` when
    ///                    it has, `null` for the `DELETES` group (new, changed and deleted clients)
    record Member(CareClient src, String mergeResult, NameStandardization.Output name) {

        /// `PKEY_SRC_OBJECT_PTY` = `TO_CHAR(CARE_ID)`
        String pkey() {
            return src.careId();
        }

        String roleKey() {
            return memberRole(pkey());
        }

        /// `B` (moved away) and `D` (deleted) rows are end-dated.
        boolean endDated() {
            return in(src.recType(), "B", "D");
        }

        LocalDateTime periodStart() {
            return endDated() && src.careLastupDt() != null ? src.careLastupDt().minusDays(1) : src.careLastupDt();
        }

        LocalDateTime periodEnd() {
            return endDated() ? src.careLastupDt() : null;
        }

        LocalDateTime lastUpdated(EtlContext ctx) {
            return endDated() ? ctx.runStart().minusHours(1) : ctx.runStart();
        }

        /// `MRG_CARE_ID`: the target of a case move MDM has not merged yet, else the CARE id.
        String mergedCareId() {
            return "N".equals(mergeResult) ? src.targetId() : src.careId();
        }

        /// `SRC_LAST_UPDATE_DATE` = `IIF(ISNULL(CARE_LASTUP_DT), INSERT_DATE, CARE_LASTUP_DT)`
        LocalDateTime sourceLastUpdated() {
            return nvl(src.careLastupDt(), src.insertDate());
        }
    }

    /// One `ALT_ID_RECORD` occurrence of `NRML_ALT_ID`.
    record AlternateId(String type, String value, ExceptionInfo exception) {}

    private final CreCareClientsDeltaRepository careClients;
    private final CrePartyXrefRepository crossReferences;
    private final CrePartyHmrgRepository mergeHistory;
    private final CreSourceMergeRepository sourceMerges;
    private final CrePartyRepository parties;
    private final CrePartyRoleRepository partyRoles;
    private final CreAddressRepository addresses;
    private final CrePhoneRepository phones;
    private final CreAlternateIdRepository alternateIds;
    private final BadRecordRepository badRecords;
    private final AddressValidator validator;

    public CreCareClientsService(CreCareClientsDeltaRepository careClients, CrePartyXrefRepository crossReferences,
            CrePartyHmrgRepository mergeHistory, CreSourceMergeRepository sourceMerges, CrePartyRepository parties,
            CrePartyRoleRepository partyRoles, CreAddressRepository addresses, CrePhoneRepository phones,
            CreAlternateIdRepository alternateIds, BadRecordRepository badRecords, AddressValidator validator) {
        this.careClients = careClients;
        this.crossReferences = crossReferences;
        this.mergeHistory = mergeHistory;
        this.sourceMerges = sourceMerges;
        this.parties = parties;
        this.partyRoles = partyRoles;
        this.addresses = addresses;
        this.phones = phones;
        this.alternateIds = alternateIds;
        this.badRecords = badRecords;
        this.validator = validator;
    }

    /// The `IdqMapInitQuery`.
    public List<CareClient> fetchCareClients() {
        return careClients.fetchCareClients();
    }

    /// `LKP_XREF_*` and `LKP_HMRG_*`: cross-references and merge history of the CRE parties in MDM.
    public Lookups fetchMergeLookups() {
        var history = mergeHistory.fetchMergeHistory();
        return new Lookups(crossReferences.fetchCrossReferences().stream()
                .filter(x -> x.pkeySrcObject() != null)
                .collect(Collectors.toMap(PartyXref::pkeySrcObject, Function.identity(), (a, b) -> a)),
                history.stream().map(MdmBaseTables.PartyHmrg::srcRowidObject).filter(Objects::nonNull)
                        .collect(Collectors.toSet()),
                history.stream().map(MdmBaseTables.PartyHmrg::tgtRowidObject).filter(Objects::nonNull)
                        .collect(Collectors.toSet()));
    }

    /// `RTR_MERGES.DELETES`: `ISNULL(MAINT_FLAG) OR (MAINT_FLAG = 'D' AND REC = 'CASEDEL')`. Every other row (a case
    /// move, or a move target with a maintenance flag) goes to the default group and through the merge lookups.
    static boolean regularOrDeleted(CareClient r) {
        return r.maintFlag() == null || ("D".equals(r.maintFlag()) && "CASEDEL".equals(r.rec()));
    }

    /// `EXP_SRC_TGT_MRG_RSLT.ORIG_ROWID_OBJECT_DESC`: `N` when neither the source nor the target record of the move
    /// has a merge history (by its original record), else `Y`.
    static String mergeResult(CareClient r, Lookups lookups) {
        var source = originalRecord(r.sourceId(), lookups);
        var target = originalRecord(r.targetId(), lookups);
        boolean history = Stream.of(source, target).filter(Objects::nonNull)
                .anyMatch(orig -> lookups.mergedSources().contains(orig) || lookups.mergedTargets().contains(orig));
        return history ? "Y" : "N";
    }

    private static String originalRecord(String careId, Lookups lookups) {
        var xref = careId == null ? null : lookups.crossReferences().get(careId);
        return xref == null ? null : xref.origRowidObject();
    }

    private static String record(String careId, Lookups lookups) {
        var xref = careId == null ? null : lookups.crossReferences().get(careId);
        return xref == null ? null : xref.rowidObject();
    }

    public MappingOutput transform(List<CareClient> rows, Lookups lookups, EtlContext ctx) {
        var merges = new ArrayList<CreSources.SourceMerge>();
        var bad = new ArrayList<BadRecord>();
        var valid = new ArrayList<Member>();
        for (var r : rows) {
            String mergeResult = null;
            if (!regularOrDeleted(r)) {
                mergeResult = mergeResult(r, lookups);
                if ("N".equals(mergeResult)) {
                    // FLTR_CRE_MRG -> Write_CRE_SRC_MRG
                    merges.add(new CreSources.SourceMerge(record(r.sourceId(), lookups),
                            record(r.targetId(), lookups), ctx.runStart()));
                }
            }
            var name = NameStandardization.standardize(new NameStandardization.Input(r.firstnm(), null,
                    r.lastnm(), null, null, r.lastSuf(), SRC), ctx);
            var member = new Member(r, mergeResult, name);
            // rtr_Valid_Members.VALID_MEMBERS: LENGTH(RTRIM(LTRIM(FIRSTNM))) > 0 AND LENGTH(RTRIM(LTRIM(LASTNM))) > 0
            if (hasText(name.first()) && hasText(name.last())) {
                valid.add(member);
            } else {
                bad.addAll(nameExceptions(member, ctx));
            }
        }
        // SRT_VALID_MEMBERS (key ascending, REC_TYPE descending) + Filt_DeDeup_Seq1: one row per CARE id, I before D
        // before B before A.
        var members = Rows.firstPerKey(Rows.sorted(valid, Rows.<Member, String>asc(Member::pkey)
                .thenComparing(Rows.desc(m -> m.src().recType()))), Member::pkey);

        var partyRows = new ArrayList<CreTargets.Party>();
        var roleRows = new ArrayList<CreTargets.PartyRole>();
        var addressRows = new ArrayList<CreTargets.Address>();
        var phoneRows = new ArrayList<CreTargets.Phone>();
        var alternateIdRows = new ArrayList<CreTargets.AlternateId>();
        for (var m : members) {
            party(m, ctx, partyRows, roleRows, bad);
            address(m, ctx, addressRows, bad);
            phone(m, ctx, phoneRows, bad);
            alternateIds(m, ctx, alternateIdRows, bad);
        }
        return MappingOutput.empty()
                .load(TargetBatch.append(CreSources.SourceMerge.class, merges))
                .load(TargetBatch.append(CreTargets.Party.class, partyRows))
                .load(TargetBatch.append(CreTargets.PartyRole.class, roleRows))
                .load(TargetBatch.append(CreTargets.Address.class, addressRows))
                .load(TargetBatch.append(CreTargets.Phone.class, phoneRows))
                .load(TargetBatch.append(CreTargets.AlternateId.class, alternateIdRows))
                // the unique key of EXC_STG_BAD_REC_MEMB rejects a repeated row (a CARE id read twice, or the source and
                // target of an unmerged move logging under the target id); IDQ keeps the first and carries on
                .reject(Rows.firstPerKey(bad, BadRecord::key));
    }

    /// `rtr_Invalid_First_Last_Name`: a missing first and a missing last name each write a row, but only when the
    /// exception is configured in `EXC_LOOKUP_CODE_VALUE` (the router tests the looked-up values).
    static List<BadRecord> nameExceptions(Member m, EtlContext ctx) {
        var src = m.src();
        var name = m.name();
        var first = ctx.exception(isMissing(name.first()) ? "Missing_First_Name" : null);
        var last = ctx.exception(isMissing(name.last()) ? "Missing_Last_Name" : null);
        return Stream.of(
                first.configured() ? ctx.badRecord().ids(src.careId(), null, null).exception(first)
                        .attribute("First Name", src.firstnm())
                        .name(null, name.first(), null, name.last(), name.suffix())
                        .person(src.birthDt(), src.sex(), null).build() : null,
                last.configured() ? ctx.badRecord().ids(src.careId(), null, null).exception(last)
                        .attribute("Last Name", src.lastnm())
                        .name(null, name.first(), null, name.last(), name.suffix())
                        .person(src.birthDt(), src.sex(), null)
                        .address(null, src.street(), null, src.city(), src.cnty(), src.state(), src.zip(),
                                src.zipsuf(), null).build() : null)
                .filter(Objects::nonNull).toList();
    }

    /// `EXP_PTY` -> gender, ethnicity and race mapplets -> `C_S_CRE_PTY`; `EXP_PTY_RLE_HOLD` -> `C_S_CRE_PTY_RLE`.
    /// The birth date is loaded as reported (CRE has no birth-date rule).
    static void party(Member m, EtlContext ctx, List<CreTargets.Party> parties, List<CreTargets.PartyRole> roles,
            List<BadRecord> bad) {
        var src = m.src();
        var name = m.name();
        var gender = PersonRules.gender(src.sex(), "Indv", SRC, ctx);
        var ethnicity = PersonRules.codeValue("ETHNICITY", SRC, src.fedeth(), "Invalid_Ethnicity", ctx);
        var race = PersonRules.codeValue("RACE", SRC, src.race(), "Invalid_Race", ctx);
        // EXP_PTY_HOLD / EXP_PTY_RLE_HOLD: PERIOD_END_DATE = start + 1 day for B and D rows
        var periodEnd = m.endDated() && m.periodStart() != null ? m.periodStart().plusDays(1) : null;
        var lastUpdated = m.lastUpdated(ctx);
        parties.add(new CreTargets.Party(m.pkey(), MdmAudit.srcRowid(m.pkey()).period(m.periodStart(), periodEnd)
                .lastUpdated(lastUpdated).created(lastUpdated).sourceUpdated(m.sourceLastUpdated()),
                new Columns.PartyWithoutFlag("Indv", null, name.first(), null, name.last(), name.suffix(), name.full(),
                        gender.value(), src.birthDt(), name.srcFull(), ethnicity.value(), src.fedeth(), race.value(),
                        src.race())));
        // EXP_PTY_RLE_HOLD.LAST_UPDATE_DATE is the run start for every row (no hour back for B and D rows)
        roles.add(new CreTargets.PartyRole(m.roleKey(), MdmAudit.srcRowid(m.roleKey()).period(m.periodStart(),
                periodEnd).lastUpdated(ctx.runStart()).created(ctx.runStart()).sourceUpdated(m.sourceLastUpdated()),
                new Columns.PartyRole(m.pkey(), EtlPatterns.MEMBER)));

        // fltr_Gender_Exc, fltr_Suffix_exc, Filt_Bad_Ethnicity_Cd, Filt_Bad_Race_Cd
        if (gender.exception().configured()) {
            bad.add(ctx.badRecord().ids(src.careId(), null, null).exception(gender.exception())
                    .attribute("Gender", src.sex()).person(null, src.sex(), null).build());
        }
        if (name.suffixExceptionCode() != null) {
            bad.add(ctx.badRecord().ids(src.careId(), null, null).exception(ctx.exception(name.suffixExceptionCode()))
                    .attribute("Name Suffix", src.lastSuf()).build());
        }
        if (ethnicity.exception().configured()) {
            bad.add(ctx.badRecord().ids(src.careId(), null, null).exception(ethnicity.exception())
                    .attribute("FEDETH", src.fedeth()).build());
        }
        if (race.exception().configured()) {
            bad.add(ctx.badRecord().ids(src.careId(), null, null).exception(race.exception())
                    .attribute("RACE", src.race()).build());
        }
    }

    /// `EXP_ADDRESSES` -> `LKP_STATE_CODE` -> `RTR_US_ADDRESSES`:
    ///
    /// * US (the state does not translate to `99`): `mplt_Global_Addr_Validation`, then `RTR_VALID_ADDRESS`;
    /// * outside the US: city and street title cased, state `99`, country `ZZ`, then `RTR_VALID_NON_US_ADDRESSES`
    ///   (city and street present).
    ///
    /// Good addresses go to `C_S_CRE_PTY_RLE_ADDR` (one per member, type `002`); the others to the exception queue
    /// with the looked-up `Invalid_Address` (NULL code when it is not configured).
    void address(Member m, EtlContext ctx, List<CreTargets.Address> addresses, List<BadRecord> bad) {
        var src = m.src();
        var source = new Columns.SourceAddress(src.street(), null, src.city(), src.cnty(), src.state(), "US",
                src.zip(), src.zipsuf());
        // LKP_STATE_CODE: V_LOOKUP_CODE_VALUE on source value and source system, any code type
        var stdState = src.state() == null ? null : ctx.reference().masterCode(null, SRC, src.state()).orElse(null);
        Columns.ValidatedAddress validated = null;
        AddressValidator.Result av = null;
        if (stdState == null || !NON_US_STATE.equals(stdState)) {
            av = validator.validate(new AddressValidator.Input(src.street(), null, src.city(), src.state(),
                    concat(src.zip(), "-", src.zipsuf()), "US", SRC), ctx.reference());
            if (deliverable(av)) {
                validated = new Columns.ValidatedAddress(av.deliveryAddressLine1(), av.deliveryAddressLine2(),
                        av.buildingName(), av.subBuildingNumber(), av.city(), county(av.stateFips(), av.countyFips()),
                        av.stateFips(), av.countryIso2(), av.zip5(), av.zip4(), av.latitude(), av.longitude(),
                        av.matchCode(), av.mailabilityScore(), av.addressType(), av.organizationDescriptor(),
                        av.organizationName(), av.buildingNumber(), av.subBuildingComplete(),
                        av.subBuildingDescriptor(), av.geocodingStatus(), av.residentialDeliveryIndicator());
            }
        } else if (src.city() != null && src.street() != null) {
            validated = new Columns.ValidatedAddress(initcap(src.street()), null, null, null, initcap(src.city()),
                    county(NON_US_STATE, src.cnty()), NON_US_STATE, "ZZ", src.zip(), src.zipsuf(), null, null, null,
                    null, null, null, null, null, null, null, null, null);
        }
        if (validated == null) {
            var exception = ctx.badRecord().ids(src.careId(), null, null).exception(lookedUp(ctx, "Invalid_Address"))
                    .attribute("Address", concat(src.street(), " ", null, " ", src.city(), " ", src.state(), " ",
                            src.zip()))
                    .address(null, src.street(), null, src.city(), src.cnty(), src.state(), src.zip(), src.zipsuf(),
                            "US");
            if (av != null) {
                exception.addressDoctor(av.matchCode(), av.matchCodeDescription(), av.mailabilityScore());
            }
            bad.add(exception.build());
            return;
        }
        var key = pipe(m.roleKey(), ADDRESS_TYPE);
        var lastUpdated = m.lastUpdated(ctx);
        addresses.add(new CreTargets.Address(key, MdmAudit.srcRowid(key).period(m.periodStart(), m.periodEnd())
                .lastUpdated(lastUpdated).created(lastUpdated).sourceUpdated(src.careLastupDt()),
                new Columns.AddressWithUsage(m.roleKey(), ADDRESS_TYPE, ADDRESS_TYPE, "Primary", "Payer",
                        "Member Addr", null, validated, source)));
    }

    /// `RTR_VALID_ADDRESS.VALID_ADDRESSES`: `(TO_INTEGER(MailabilityScore) >= 3 OR NOT IN(SUBSTR(MatchCode, 1, 1),
    /// 'I', 'N')) AND NOT ISNULL(state FIPS)`. Both tests are NULL when AddressDoctor returns no score and no match
    /// code, so such an address (every address with the pass-through validator) is an exception.
    static boolean deliverable(AddressValidator.Result av) {
        var score = av.mailabilityScore();
        boolean scored = Infa.isNumber(score) && new BigDecimal(score.strip()).intValue() >= 3;
        boolean matched = av.matchCode() != null && !in(substr(av.matchCode(), 1, 1), "I", "N");
        return (scored || matched) && av.stateFips() != null;
    }

    /// `EXP_PTY_RLE_ADDR_HOLD.out_COUNTY_CD`: `996` outside Texas, `998` when Texas has no county. A NULL state does
    /// not compare as "outside Texas" (`NULL <> '48'` is not true).
    static String county(String stateFips, String countyFips) {
        if (stateFips != null && !stateFips.equals("48")) {
            return "996";
        }
        return countyFips == null ? "998" : countyFips;
    }

    /// `FLTR_NULL_PHONE` -> `rule_Phone_Std` -> `RTR_VALID_PHONE`. Only the number is linked into the rule (its
    /// source system and usage inputs are not), so the toll-free check for CRE main numbers never runs. A phone is
    /// loaded unless the looked-up exception code is set.
    static void phone(Member m, EtlContext ctx, List<CreTargets.Phone> phones, List<BadRecord> bad) {
        var src = m.src();
        if (src.phone() == null) {
            return;
        }
        var phone = ContactRules.phone(src.phone(), null, null, ctx);
        if (phone.exception().configured()) {
            bad.add(ctx.badRecord().ids(src.careId(), null, null).exception(phone.exception())
                    .attribute("Telephone", phone.value()).phones(phone.value(), null, null).build());
            return;
        }
        var key = pkeyPhone(m.pkey(), phone.value());
        var lastUpdated = m.lastUpdated(ctx);
        phones.add(write2TargetPhone(CreTargets.Phone::new, key, m.roleKey(), "Telephone", "001", phone.value(),
                "Primary", MdmAudit.srcRowid(key).period(m.periodStart(), m.periodEnd()).lastUpdated(lastUpdated)
                        .created(lastUpdated).sourceUpdated(src.careLastupDt())));
    }

    /// `<CARE id>|Member|Telephone|001|<phone>`
    public static String pkeyPhone(String partyKey, String phone) {
        return pipe(memberRole(partyKey), "Telephone", "001", phone);
    }

    /// `NRML_ALT_ID`: the CARE id (`rule_CARE_ID_Std`, of the merged CARE id), the Medicaid id (`RECIP_NO`,
    /// `rule_MEDICAID_ID_Std`) and the SSN (`U` / `N` blanked; `Invalid_SSN` as looked up). The type is translated
    /// through `LOOKUP_CODE_VALUE` (source system CRE, any code type); ids without a value are dropped
    /// (`FLTR_NULL_ALT_ID_SEQ1`), ids with an exception go to the exception queue (`RTR_VALID_ALT_ID`).
    static void alternateIds(Member m, EtlContext ctx, List<CreTargets.AlternateId> ids, List<BadRecord> bad) {
        var src = m.src();
        var medicaid = IdentifierRules.medicaidId(src.recipNo(), ctx);
        var ssn = in(src.ssn(), "U", "N") ? null : src.ssn();
        var ssnException = ssn != null && !IdentifierRules.ssnIsValid(ssn) ? lookedUp(ctx, "Invalid_SSN")
                : ExceptionInfo.NONE;
        var occurrences = List.of(
                new AlternateId("CARE ID", SpecialCharacters.remove(m.mergedCareId()), ExceptionInfo.NONE),
                new AlternateId("Medicaid ID", medicaid.value(), medicaid.exception()),
                new AlternateId("SSN", ssn, ssnException));
        for (var id : occurrences) {
            if (id.value() == null) {
                continue;
            }
            var type = ctx.reference().codeValue(null, SRC, id.type());
            var typeCode = type.map(t -> t.mstrRefCode()).orElse(null);
            if (id.exception().present()) {
                // EXP_ALT_ID_EXC_HOLD: SRC_SYS is the lookup's (NULL when the type does not translate)
                bad.add(BadRecords.of(type.isPresent() ? SRC : null, ctx.mappingName(), ctx.runStart())
                        .ids(m.mergedCareId(), null, null).exception(id.exception())
                        .attribute(type.map(t -> t.mstrRefLabel()).orElse(null), id.value()).build());
                continue;
            }
            var key = pkeyAlternateId(m.pkey(), typeCode, id.value());
            ids.add(new CreTargets.AlternateId(key, MdmAudit.srcRowid(key).period(m.periodStart(), m.periodEnd())
                    .lastUpdated(m.lastUpdated(ctx)).sourceUpdated(src.careLastupDt()),
                    new Columns.AlternateIdWithoutCvInd(m.roleKey(), typeCode,
                            in(id.value(), "U", "N") ? null : id.value(), "Issued", typeCode)));
        }
    }

    /// `<CARE id>|Member|<type master code>|<id>`
    public static String pkeyAlternateId(String partyKey, String typeCode, String value) {
        return pipe(memberRole(partyKey), typeCode, value);
    }

    /// The code as returned by the `EXC_LOOKUP_CODE_VALUE` lookup: nothing when it is not configured.
    private static ExceptionInfo lookedUp(EtlContext ctx, String code) {
        var exception = ctx.exception(code);
        return exception.configured() ? exception : ExceptionInfo.NONE;
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(CreSourceMergeRepository.TABLE, insertSourceMerges(output.rows(CreSources.SourceMerge.class)));
        loaded.put(CrePartyRepository.TABLE, insertParties(output.rows(CreTargets.Party.class)));
        loaded.put(CrePartyRoleRepository.TABLE, insertPartyRoles(output.rows(CreTargets.PartyRole.class)));
        loaded.put(CreAddressRepository.TABLE, insertAddresses(output.rows(CreTargets.Address.class)));
        loaded.put(CrePhoneRepository.TABLE, insertPhones(output.rows(CreTargets.Phone.class)));
        loaded.put(CreAlternateIdRepository.TABLE, insertAlternateIds(output.rows(CreTargets.AlternateId.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int insertSourceMerges(List<CreSources.SourceMerge> rows) {
        return sourceMerges.insertAll(rows).size();
    }

    int insertParties(List<CreTargets.Party> rows) {
        return parties.insertAll(rows).size();
    }

    int insertPartyRoles(List<CreTargets.PartyRole> rows) {
        return partyRoles.insertAll(rows).size();
    }

    int insertAddresses(List<CreTargets.Address> rows) {
        return addresses.insertAll(rows).size();
    }

    int insertPhones(List<CreTargets.Phone> rows) {
        return phones.insertAll(rows).size();
    }

    int insertAlternateIds(List<CreTargets.AlternateId> rows) {
        return alternateIds.insertAll(rows).size();
    }
}
