package com.idq.cli.config;

/// Snowflake connection of `etl_process=SNOWFLAKE_SP`, read from `application.properties`:
///
/// | property                  | field        | default                                   |
/// |---------------------------|--------------|-------------------------------------------|
/// | `idq.snowflake.url`       | [#url]       | `${SNOWFLAKE_JDBC_URL:}`                  |
/// | `idq.snowflake.user`      | [#user]      | `${SNOWFLAKE_USER:}`                      |
/// | `idq.snowflake.password`  | [#password]  | `${SNOWFLAKE_PASSWORD:}`                  |
///
/// The URL carries account, database, schema, warehouse and role, e.g.
/// `jdbc:snowflake://<account>.snowflakecomputing.com/?db=MDM&schema=STAGING&warehouse=ETL_WH&role=ETL`. Other
/// authenticators (key pair, SSO) go into the URL as Snowflake JDBC parameters. Credentials come from the environment
/// only; [#toString] never prints the password.
public record SnowflakeSettings(String url, String user, String password) {

    public boolean configured() {
        return !url.isBlank();
    }

    @Override
    public String toString() {
        return "SnowflakeSettings[url=" + url + ", user=" + user + ", password=" + (password.isEmpty() ? "" : "***")
                + "]";
    }
}
