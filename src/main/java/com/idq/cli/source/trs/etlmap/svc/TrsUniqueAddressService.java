package com.idq.cli.source.trs.etlmap.svc;

import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.in;
import static com.idq.cli.core.Infa.ltrim;
import static com.idq.cli.core.Infa.rtrim;
import static com.idq.cli.core.Infa.substr;
import static com.idq.cli.core.Infa.trim;

import com.idq.cli.config.EtlSettings;
import com.idq.cli.core.AddressPatterns;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecordRepository;
import com.idq.cli.core.rules.AddressValidator;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.etldb.models.TrsQueryRows.DistinctAddress;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.trs.etldb.repo.TrsIndvAddrDeltaRepository;
import com.idq.cli.source.trs.etldb.repo.TrsUniqueAddressDeltaRepository;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/// `m_Tgt_C_S_TRS_Addr_1` - validates each distinct TIERS address once into `STG_TRS_D_UNQ_ADDR`.
/// See [docs/mappings/011_m_Tgt_C_S_TRS_Addr_1.md].
@Service
public class TrsUniqueAddressService {

    public static final MappingInfo INFO = MappingInfo.of("011", "m_Tgt_C_S_TRS_Addr_1", SourceSystem.TRS,
            List.of(TrsSources.UniqueAddressDelta.class), List.of(TrsSources.IndvAddrDelta.class,
            TrsSources.CdRef.class));

    private final AddressValidator validator;

    private final TrsIndvAddrDeltaRepository indvAddrDelta;
    private final TrsUniqueAddressDeltaRepository uniqueAddresses;
    private final BadRecordRepository badRecords;
    private final EtlSettings settings;

    public TrsUniqueAddressService(TrsIndvAddrDeltaRepository indvAddrDelta,
            TrsUniqueAddressDeltaRepository uniqueAddresses, BadRecordRepository badRecords, AddressValidator validator,
            EtlSettings settings) {
        this.indvAddrDelta = indvAddrDelta;
        this.uniqueAddresses = uniqueAddresses;
        this.badRecords = badRecords;
        this.settings = settings;
        this.validator = validator;
    }

    /// The `IdqMapInitQuery`.
    public List<DistinctAddress> fetchDistinctAddresses() {
        return indvAddrDelta.fetchDistinctAddresses();
    }

    /// TIERS directions `EA`, `NO`, `SO`, `WE` are shortened to their first letter (USPS style).
    public static String direction(String code) {
        return in(code, "EA", "NO", "SO", "WE") ? substr(code, 0, 1) : code;
    }

    /// Street number, fraction, direction, street name and street type description.
    public static String line1(DistinctAddress a, String streetTypeDescription) {
        return ltrim(rtrim(concat(a.addrStNum(), " ", a.addrStNumFrac(), " ", direction(a.addrStDirCd()), " ",
                a.addrStNm(), " ", streetTypeDescription)));
    }

    /// Dwelling type, apartment number and free-form address line.
    public static String line2(DistinctAddress a) {
        return trim(concat(a.addrDwellingTypeCd(), " ", a.addrAptNum(), " ", a.addrLine()));
    }

    public MappingOutput transform(List<DistinctAddress> rows, NoLookups lookups, EtlContext ctx) {
        var addresses = Rows.lastPerKey(rows, DistinctAddress::addrId).stream().map(a -> {
            var streetType = ctx.reference().streetTypeDescription(a.addrStTypeCd()).orElse(null);
            var l1 = line1(a, streetType);
            var l2 = line2(a);
            var av = validator.validate(new AddressValidator.Input(l1, l2, a.addrCity(), a.addrStateCd(),
                    concat(a.addrZip5(), "-", a.addrZip4()), "US", "TRS"), ctx.reference());
            return new TrsSources.UniqueAddressDelta(a.addrId(), av.deliveryAddressLine1(), av.deliveryAddressLine2(),
                    av.buildingName(), av.subBuildingNumber(), av.city(), av.countyFips(), av.stateFips(),
                    av.countryIso2(), av.zip5(), av.zip4(), av.latitude(), av.longitude(), av.matchCode(),
                    av.matchCodeDescription(), av.mailabilityScore(), av.addressType(), av.organizationDescriptor(),
                    av.organizationDepartment(), av.organizationName(), av.buildingNumber(),
                    av.subBuildingComplete(), av.subBuildingDescriptor(), av.geocodingStatus(),
                    av.residentialDeliveryIndicator(), AddressPatterns.decimal(av.resultPercentage()),
                    av.earlyWarningCode(),
                    av.cassErrorCode(), av.deliveryPointValidation(), l1, l2, a.addrCity(), null, a.addrStateCd(),
                    "US", a.addrZip5(), a.addrZip4());
        }).toList();
        return MappingOutput.empty().load(TargetBatch.append(TrsSources.UniqueAddressDelta.class, addresses));
    }

    @Transactional
    public Map<String, Integer> load(MappingOutput output) {
        var loaded = new LinkedHashMap<String, Integer>();
        loaded.put(TrsUniqueAddressDeltaRepository.TABLE,
                insertUniqueAddresses(output.rows(TrsSources.UniqueAddressDelta.class)));
        if (!output.badRecords().isEmpty()) {
            loaded.put(BadRecordRepository.TABLE, badRecords.insertAll(output.badRecords()).size());
        }
        return loaded;
    }

    int insertUniqueAddresses(List<TrsSources.UniqueAddressDelta> rows) {
        return uniqueAddresses.insertAll(rows).size();
    }
}
