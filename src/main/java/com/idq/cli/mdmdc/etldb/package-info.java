/// The MDM (data Center) database layer: all the C_S_* tables are represented here
///
/// * `models` - entity records of the MDM tables 
/// * `repo` - one Spring Data JDBC repository per table
/// * `svc` - services that combine several repositories into one business function
package com.idq.cli.mdmdc.etldb;
