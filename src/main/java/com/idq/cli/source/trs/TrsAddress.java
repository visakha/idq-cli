package com.idq.cli.source.trs;

import static com.idq.cli.core.EtlPatterns.memberRole;
import static com.idq.cli.core.Infa.concat;
import static com.idq.cli.core.Infa.pipe;

import com.idq.cli.core.AddressPatterns;
import com.idq.cli.core.EtlContext;
import com.idq.cli.core.Infa;
import com.idq.cli.core.MappingOutput;
import com.idq.cli.core.Rows;
import com.idq.cli.core.exception.BadRecord;
import com.idq.cli.core.rules.AddressRules;
import com.idq.cli.core.rules.PersonRules;
import com.idq.cli.core.target.Columns;
import com.idq.cli.core.target.DqmAddress;
import com.idq.cli.core.target.MdmAudit;
import com.idq.cli.core.target.TargetBatch;
import com.idq.cli.domain.MappingInfo;
import com.idq.cli.domain.MemberMapping;
import com.idq.cli.domain.MemberMapping.NoLookups;
import com.idq.cli.domain.SourceMapping;
import com.idq.cli.domain.SourceSystem;
import com.idq.cli.source.trs.TrsQueries.AddressAssignment;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;

/// `m_Tgt_C_S_TRS_Addr_2` - assigns the validated addresses to member roles.
/// See [docs/mappings/012_m_Tgt_C_S_TRS_Addr_2.md].
@Component
public class TrsAddress extends SourceMapping<AddressAssignment, NoLookups>
        implements MemberMapping.Address<AddressAssignment, NoLookups> {

    public static final MappingInfo INFO = MappingInfo.of("012", "m_Tgt_C_S_TRS_Addr_2", SourceSystem.TRS,
            List.of("C_S_TRS_PTY_RLE_ADDR", "DQM_ADDRESS"), List.of(TrsSources.DIndvAddr.class,
            TrsTargets.UniqueAddress.class, TrsTargets.ValidMember.class));

    public TrsAddress(TrsQueries queries) {
        super(INFO, queries::fetchAddressAssignments, NoLookups::none);
    }

    /// `<party key>|Member|<MDM address type>|<case>|<EDG>|<effective begin YYYYMMDD>`
    public static String pkey(String partyKey, String addressTypeMaster, Long caseNum, Long edgNum,
            java.time.LocalDateTime effBeginDt) {
        return pipe(memberRole(partyKey), addressTypeMaster, Infa.toChar(caseNum), Infa.toChar(edgNum),
                Infa.toChar(effBeginDt, "yyyyMMdd"));
    }

    /// Validated address text used as the `DQM_ADDRESS` key.
    static String dqmKey(AddressAssignment a) {
        var postal = concat(a.pstlCd(), a.pstlCdExt() == null ? "" : "-" + a.pstlCdExt());
        return pipe(a.addrLn1(), a.addrLn2(), a.city(), postal, a.state(), a.cntryCd());
    }

    @Override
    public MappingOutput transform(List<AddressAssignment> rows, NoLookups lookups, EtlContext ctx) {
        var dqm = new ArrayList<DqmAddress>();
        var addresses = new ArrayList<TrsTargets.Address>();
        var bad = new ArrayList<BadRecord>();
        for (var a : rows) {
            var src = new Columns.SourceAddress(a.srcAddrLn1(), a.srcAddrLn2(), a.srcCity(), a.srcCounty(),
                    a.srcState(), a.srcCntry(), a.srcPstlCd(), a.srcPstlCdExt());
            dqm.add(dqmRow(a, src, ctx));
            var addrType = ctx.reference().masterCode("ADDR_TP", "TRS", a.addrTypeCd()).orElse(null);
            if (AddressRules.score(addrType, a.mlbltyScr(), a.vldtnMsg()) == AddressRules.Score.EXCEPTION) {
                bad.add(AddressPatterns.badData4Address(ctx, ctx.exception("Invalid_Address"), a.addrTypeCd(), src,
                        a.vldtnMsg(), a.vldtnDesc(), a.mlbltyScr(), a.effBeginDt(), a.effEndDt(), a.indvId(),
                        a.caseNum(), a.edgNum()));
                continue;
            }
            var lines = AddressRules.holdLines(a.addrLn1(), a.addrLn2());
            var key = pkey(a.ptyPk(), addrType, a.caseNum(), a.edgNum(), a.effBeginDt());
            var endDate = PersonRules.notBeyondFiftyYears(a.effEndDt(), ctx);
            var audit = MdmAudit.srcRowid(key).period(a.effBeginDt(), endDate).lastUpdated(ctx.runStart())
                    .sourceUpdated(a.createDt());
            var validated = new Columns.ValidatedAddress(lines.line1(), lines.line2(), a.bldngNm(), a.flrNum(),
                    a.city(), a.county(), a.state(), a.cntryCd(), a.pstlCd(), a.pstlCdExt(), a.lattd(), a.lngtd(),
                    a.vldtnMsg(), a.mlbltyScr(), a.addrTpCd(), a.orgDesc(), a.orgNm(), a.bldgNmbr(), a.subBldgNm(),
                    a.subBldgDesc(), a.geocdStsCd(), a.rsdntlDlvryInd());
            addresses.add(new TrsTargets.Address(key, audit, new Columns.Address(memberRole(a.ptyPk()), addrType,
                    "Primary", "Member", "Member Addr", pipe(Infa.toChar(a.caseNum()), Infa.toChar(a.edgNum())),
                    validated, src, a.effBeginDt(), endDate)));
        }
        var latestFirst = Rows.sorted(addresses, Rows.<TrsTargets.Address, String>asc(TrsTargets.Address::pkeySrcObject)
                .thenComparing(Rows.desc(r -> r.audit().srcLastUpdDt()))
                .thenComparing(Rows.desc(r -> r.columns().effEndDt()))
                .thenComparing(Rows.desc(r -> r.columns().effStrtDt())));
        return MappingOutput.empty()
                .load(TargetBatch.append(DqmAddress.class, dqm))
                .load(TargetBatch.replaceAll(TrsTargets.Address.class,
                        Rows.firstPerKey(latestFirst, TrsTargets.Address::pkeySrcObject)))
                .reject(bad);
    }

    private static DqmAddress dqmRow(AddressAssignment a, Columns.SourceAddress src, EtlContext ctx) {
        var resultPostal = concat(a.pstlCd(), a.pstlCdExt() == null ? "" : "-" + a.pstlCdExt());
        var srcPostal = concat(a.srcPstlCd(), a.srcPstlCdExt() == null ? "" : "-" + a.srcPstlCdExt());
        return new DqmAddress(a.ptyPk(), dqmKey(a), "TRS", a.addrTypeCd(), ctx.runStart(), src.srcAddrLn1(),
                src.srcAddrLn2(), src.srcCity(), src.srcState(), srcPostal, src.srcCntry(), src.srcCounty(),
                a.addrLn1(), a.addrLn2(), a.city(), a.state(), resultPostal, a.cntryCd(), a.county(), a.county(),
                a.state(), a.lattd(), a.lngtd(), a.geocdStsCd(), a.rsdntlDlvryInd(), a.orgDesc(), a.orgDept(),
                a.orgNm(), a.bldgNmbr(), a.subBldgNm(), a.mlbltyScr(), a.vldtnMsg(), a.addrdrRsltPct(),
                a.addrTpCd(), a.erlyWrngCd(), a.cassErrCd(), a.dlvryPntVldn());
    }
}
