# About this project

This is a Springboot based Application to build a Custom Java ETL that is a replacement for a legacy ETL that is built using Informatica IDQ.
The files wf_WIC_Stage_Load.xml , wf_TRS_Stage_Load_1_Ongoing.xml, wf_ECI_Stage_Load.xml, wf_FSS_Stage_Load.xml and wf_TTF_Stage_Load.xml are an 
export of the Informatica IDQ ETL Workflows one for each source TRS, ECI, FSS and TTF.

# About the data
The data falls into two Domains (A) Member   (B) Provider
The data feeds are specific to the source system (TRS, ECI, FSS and TTF) and therefore each source system has its own Source tables. The structure of the source tables are not the same across source systems.
The target tables are also specific to the source system, but all target tables share the same common structure.

The Target Tables start with C_S_

Currenty we are focusing on the Member domain.

# Further notes
The Informatica Data Quality IDQ workflow orchestrates a series of mappings, where the mappings do the actual heavy lifting of the ETL. 
In many cases the mappings invokes a query to read the source tables and the challange is that these queries carry a lot of business knowledge that is currently lacking in documentation, this is where most business knowledge resides hidden as SQL query, one of your most important task is to extract this business knowledge in Plain English, document it clearly and use Mermaid Diagrams to further represent it visually (at the component level only or Process level, with arrows).

# Data sub-domains
the sub-domains are 
- Demographics
- Phone-email
- Address
- Alternate-ID
- Alternate-Name
- Party-Managed-Attrib
- Role

Each of the source may provide one or more of the sub-domains information, and information can be partial within each of the sub-domains
Usually the Target table are one-to-one with the sub-domains, for example there are target Role table for the domain of Role.

## KEYS
Keys are most important for the target tables, in Oracle they have CHAR(14) as the data type.
Those keys that serve as Unique-Keys are also called PKEYS, PKEY_SRC_OBJECT, these keys are important and are FORMULATED in the mappings.
Those keys that serve as Foreign Keys for the Lookup Types (Example Phone Type and Address Type) can be treated as regular business fields these are NOT FORMULATED in the mappings

## STALE CODE - TimeLine and Version

VERY IMPORTANT:  the C_S_* tables have legacy timeLine enabled (Informatica MDM concept), but its stale and not used anymore
but the mappings have this stale ETL Code trying to derive VERSION_SEQ or VERSION etc columns,  ignore them completely
drop all
  timeline-related logic (VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, rank loops, and the dedup mapplet) since
  those columns won't exist on the Java entities, but keep the two non-timeline dedup cases (source SQL ROW_NUMBER and
  unique PKEY at write time), flagging them in docs, and save this as a memory going forward.
  any ETL mapping components like the Expression Transformation, when the refere to these ports, ignore them



# Business Logic extraction
create a markdown file for each of the mappings and Extract the business logic and document it with mermaid Diagrams, also include the below items
	- SQL query that the mapping invokes as its first task (lets coin the term for this SQL, lets call it  `idq-map-init-query` or `IdqMapInitQuery` )
		-- put the name of the SQL Query in its own sub header and give it a short name (max 40 chars) that is contextual, numbers are allowed 
	- Mention the Java Entity Class that holds the data from this query, and the Java Named Query Interface that will invoke this query from the Oracle DB
		- when generating the java code, link back to the markdown file and section within the file
	- usually there will be one SQL query per mappings, but in few cases the mapping will invole additional SQLs either as first steps and/or subsequent steps, in those cases too perform the same above steps to keep it all consistent
	- finally put a sub section called 'java implementation' and in that note down the summary of Java classes and records and Enums involved and how the ETL logic is implemented in Java
Name of the file should be the same as the mapping with a numeric prefix like 001_<name of the mapping>.md

NOTE: some queries that are embedded in the mappings have 'stale' filters values that are hard coded and makes no sense, ingore those kind of filters and note it down in the documentation and remove it from IdqMapInitQuery and other queries.

# About the SpringBoot and Java code guidelines
guidelines as below
- use Spring Data JDBC and **do not use JPA**
	- do not drop tables
	- currently the database is Oracle
- structure the code in such a way that the Interfaces are at the domain and sub-domain level, while the implementation is at the source system level.
- structure the code in such a way that there are common Interfaces specfic to the ETL common patterns that you had identified, sample are as below
	- fetchIdqMapInitQueryResults, write2TargetEmail, write2TargetPhone, nameStandarization, badData4name, badData4Email, badData4DeathDate, sqlFilter4lastRunDate, etlFilter4lastRunDate, timeStampNow etc (you can invent non-confusing interfaces and method signatures that is pragmatic and joy to read)
- Since the Target tables across all the sources share the same structure they can extend a common class or record or sealed class , use your best judement
	- this will allow code sharing via Generics and allow for functional programming and Fluent API design, all these are important
- Max length of the code Line is 120 chars
- use the Java 27 SDK at C:\Users\vamsi\jdk\zulu27
- use latest language features like Switch Expressions, Functional Interfaces, use streams extensively, sealed 
- use Records and ENUMs over classes where applicable
- the code should be functional in design and feel like reading a requirements document with fluent code readability.
- make the class members public as much as posible so that the noise of getters and setters is eliminated mostly.
- Write Better JavaDoc in Java with Markdown Comments
- do not write comments where the code is clear and short
- do not write excessive code
- maintain the Logic as implemented in the IDQ Mappings, do not take short cuts or short circuit the data flows.
- the code in the mapplets is independent of the source system data flow logic, so keep that code in the common package
- Adopt SOLID principles
- design the ETL flow in java in fluent API fashion
- do not invent any custom Lightweight SQL ORM like functionality, I want to use Spring Data JDBC with Native Queries for all those complex queries derived from the ETL Exports
- DO NOT DROP the Database Tables, where there is a need to drop, those tables should be whitelisted and read from a config file.
- **important** no emoji or other special unicode characters in the comments, code and documentation anywhere, they mess up the console outputs. color coding is allowed but keep it to the minimal.
- the pom.xml is already downloaded, use it for the versions etc

# Scope 
	Some of the mappings do things like Data Standarizations (like First Name and Last Name standardizations), Address Standarizations and cleaning etc, these are non-critical to the core-etl, 
	Some of the mappings do data validations to write to 'Bad' data tables , these are non-critical to the core-etl, 
	the non-critical aspects are in the scope but do not spend time beyond the minimal.
	
	## out of scope
	The following aspects are considered out of scope for the this project:
	- Deactivations Mappings and workflows
	- ReActivations Mappings and workflows

# Oracle DB
	I have an Oracle OCI free account, details as below, use it
	Access Details
	Cloud Account: vvegi
	Username: v_vegi@yahoo.com
	Password: oraTime_n0w
		Reference Number 61e9e1ab
	https://cloud.oracle.com/?region=us-chicago-1
	 
	Tenant ID
	ocid1.ten


	Autonomous AI Database Serverless
	Conmpartment : vvegi (root)
	OCI4IDQ
	User Name: ADMIN / OraDBAllG00d_
	Char Set: AL32UTF8
	National Char Set: AL16UTF16

## wallet
There is a wallet directory that you can use the login into the OCI, the password is  oraTime_n0w
	
# Mocking
	Mocking is allowed to simulate the Shell script basing on the Config (mock_infacmd=True) 
	Mocking the data is allowed in the Test Fixtures basing on the Config (mock_data=True)

# The Shell Script
The shell script invokes the IDQ CLI, this CLI is the `IDQ ETL Workflow command`   applicable only when the property `etl_process` is `IDQ` i.e `etl_process=IDQ` for Informatica IDQ.
The other option for this property is 'JAVA' i.e `etl_process=JAVA` in which case the CLI is bypassed and the Java ETL logic is applied instead.


# instructions for unit testing for PKEY
for each of the mapping identify its target table(s),  write a Unit test cases to verify the PKEY_SRC_OBJECT as mapped to the Target Table, for example  for the mapping m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing the  target table is C_S_TRS_PTY_MNG_ATTR,  write  the unit test case named m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing_pkey_test the assertion should verify the PKEY formulation. 

# What is etl_process in the propertues
The `etl_process` setting determines which ETL process should be executed.
- If etl_process is set to 'IDQ', the Informatica IDQ mappings will be used for the ETL via command line shell.
- If etl_process is set to 'JAVA', the JAva-based ETL code will be used for the ETL. (note: this is the default)

# CLI driven usage
I want to have the ability to use this application via the CLI, and use the spring-shell-starter  the library to build the CLI interface. This will allow me to define commands, options, and arguments in a structured way, and provide automatic help and completion features.

The CLI will provide commands to execute different workflows, run unit tests and BDD Test scenarios, it will read the application.properties files to manage manage its behavior.

The below are the menu actions I want:
- `show-menu`: Display the available CLI commands and options.
- `exit`: Exit the CLI application.
- `show-domains`: shows the supported domains and the mappings that are associated with it. (across all source systems)
- `show-sources`: shows the supported source systems, the source tables.
- `latch-source-system`: Latch a specific source system for processing.
- `unlatch-source-system`: Unlatch a specific source system to stop processing it.
- `show-latched-source`: Display all currently latched source systems. only one source system can be latched at a time.
- `latch-target-table`: Latch a specific target table (C_S_*) for processing. requirement `latch-source-system` must be done.
- `show-latched-domains`: Display all currently latched domains. one or more domains can be latched at a time.
- `show-source-mapping`: shows the mappings associated for the latches {`latch-target-table`, `latch-source-system`}. this allows for the user to invoke action `latch-mapping`
- `latch-mapping`: Latch a specific mapping for processing. requirement `latch-target-table` and `latch-source-system` must be done.
- `show-sample-data`: Display sample data for the currently latched mapping.
- `unlatch-mapping`: Unlatch a specific mapping to stop processing it.
- `unlatch-target-table`: Unlatch a specific target table to stop processing it.
- `fill-sample-mock-data`: Fill sample data for the currently latched mappings, source tables. requirement `latch-mapping` must be done. This whould invoke a function called `fill_sample_mock_data_<mapping_name>` to populate the sample data, where `<mapping_name>` is the name of the currently latched mapping. This function should be implemented using the appropriate logic to generate mock data for the mapping. use Faker for the data generation.
- `fill-sample-real-data`: Fill sample data for the currently latched mappings, source tables. requirement `latch-mapping` must be done. This whould invoke a function called `fill_sample_real_data_<mapping_name>` to populate the sample data, where `<mapping_name>` is the name of the currently latched mapping. This function is an empty place holder for now.

- `run-etl`: Execute the ETL Workflow for the currently latched source system, this one runs all the mappings associated with a source system that is latched. this idea is that the mappings that are not latched will be run but may not have any effect becuase the associated source tables are empty OR we simply do not care and just ignore the success or failure of those unlatched mappings.
- `run-unit-tests`: Run all unit tests for the mappings that is currently latched.
- `help`: Show the help menu with available commands and options.

NOTE: **change the shell prompt** to show the currently latched source system and target table and mapping, in that order, delimited by `+`, providing context for the commands being executed.
- The shell prompt should always be updated whenever a latch or unlatch action is performed, ensuring that the displayed context is accurate and up-to-date.
- If no source system, target table, or mapping is latched, the shell prompt should indicate that no context is currently active.

# REST API driven usage
all the commands and actions available in the CLI can also be accessed via the REST API (use RestClient from SpringBoot) , providing programmatic control over the ETL processes, unit tests. The REST API will expose endpoints corresponding to each CLI command, allowing for integration with other systems and automation of workflows.



 

