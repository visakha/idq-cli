package com.idq.cli;

import static org.assertj.core.api.Assertions.assertThat;

import com.idq.cli.core.reference.MdmBaseTables;
import com.idq.cli.core.reference.ReferenceTables;
import com.idq.cli.source.eci.etldb.models.EciSources;
import com.idq.cli.source.fss.etldb.models.FssSources;
import com.idq.cli.source.trs.etldb.models.TrsSources;
import com.idq.cli.source.ttf.etldb.models.TtfSources;
import com.idq.cli.source.wic.etldb.models.WicSources;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.Arrays;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.jdbc.core.JdbcAggregateTemplate;
import org.springframework.data.mapping.Parameter;
import org.springframework.data.mapping.model.EntityInstantiators;
import org.springframework.data.mapping.model.ParameterValueProvider;
import org.springframework.data.relational.core.mapping.RelationalPersistentEntity;
import org.springframework.data.relational.core.mapping.RelationalPersistentProperty;
import org.springframework.data.relational.core.mapping.Table;
import org.springframework.data.relational.core.query.Query;
import org.springframework.transaction.annotation.Transactional;

/// Every source, MDM and reference entity record round-trips through Spring Data JDBC against the OCI schema: one
/// row is inserted, counted and read back, then rolled back. Backup (`BAK`/`BKP`) and date-stamped tables are never
/// modelled and are excluded here as well. Needs the wallet and network:
///
/// ```
/// mvnw test -Dtest=SourceEntitiesIT
/// ```
@Tag("oracle")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE,
        properties = {"spring.shell.interactive.enabled=false", "spring.shell.context.close=false"})
@Transactional
class SourceEntitiesIT {

    static final Pattern BACKUP_OR_DATED = Pattern.compile("BAK|BKP|BACKUP|[0-9]{6,}");

    @Autowired JdbcAggregateTemplate aggregates;

    static Stream<Class<? extends Record>> entities() {
        return Stream.of(TrsSources.class, EciSources.class, FssSources.class, TtfSources.class, WicSources.class,
                        MdmBaseTables.class, ReferenceTables.class)
                .flatMap(holder -> Arrays.stream(holder.getDeclaredClasses()))
                .filter(Class::isRecord)
                .filter(type -> !BACKUP_OR_DATED.matcher(type.getAnnotation(Table.class).value()).find())
                .map(type -> type.asSubclass(Record.class));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("entities")
    void insertsAndReadsBack(Class<? extends Record> type) {
        var before = aggregates.count(type);
        aggregates.insert(sample(type));
        assertThat(aggregates.count(type)).isEqualTo(before + 1);
        assertThat(aggregates.findAll(Query.empty().limit(5), type)).isNotEmpty();
    }

    /// Every column set to a one-character / one-digit value, which fits any column of the schema; composite keys
    /// (nested records) are filled the same way. Built through Spring Data's mapping metadata and entity instantiator.
    @SuppressWarnings("unchecked")
    <R> R sample(Class<R> type) {
        var now = LocalDateTime.now().truncatedTo(ChronoUnit.SECONDS);
        var entity = (RelationalPersistentEntity<R>) aggregates.getConverter().getMappingContext()
                .getRequiredPersistentEntity(type);
        return new EntityInstantiators().getInstantiatorFor(entity).createInstance(entity,
                new ParameterValueProvider<RelationalPersistentProperty>() {
                    @Override
                    public <T> T getParameterValue(Parameter<T, RelationalPersistentProperty> parameter) {
                        var parameterType = parameter.getType().getType();
                        return (T) (parameterType.isRecord() ? sample(parameterType)
                                : switch (parameterType.getSimpleName()) {
                                    case "String" -> "1";
                                    case "Long" -> 1L;
                                    case "Integer" -> 1;
                                    case "BigDecimal" -> BigDecimal.ONE;
                                    case "LocalDateTime" -> now;
                                    default -> null;
                                });
                    }
                });
    }
}
