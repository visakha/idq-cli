/// The ETL machinery shared by every source system.
///
/// Why it exists: the IDQ mappings of the five sources repeat the same shapes (name standardization, address
/// routing, the inactive-party filter, "last row per key" consolidation). They are written once here so a mapping
/// only states what is specific to it.
///
/// * [Infa] - Informatica functions with their exact null semantics, so ported expressions read like the originals
/// * [Rows] - sorter, aggregator and filter transformations over row lists
/// * [EtlPatterns], [PartyPattern], [AddressPatterns], [InactiveStatus] - recurring mapping patterns
/// * [MappingFlow], [MappingOutput], [MappingResult], [EtlContext] - driving one mapping run and describing its
///   result
/// * [ServiceMapping], [TargetLoad] - plug a plain `source.<src>.etlmap.svc` service into the workflow runner
/// * [EntityBuilder] - typed construction of very wide records (mock data)
package com.idq.cli.core;
