/// The ECI database layer: everything that knows tables and SQL, and nothing of the IDQ transformation logic.
///
/// * `models` - entity records of the ECI tables and the rows the queries return
/// * `repo` - one Spring Data JDBC repository per table
/// * `svc` - services that combine several repositories into one business function
package com.idq.cli.source.eci.etldb;
