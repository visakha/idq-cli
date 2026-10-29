import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

public class ConnectURL {
    public static void main(String[] args) {

        // Create a variable for the connection string.
        // String connectionUrl = "jdbc:sqlserver://LEN23\\MYLOCLEN23.winwholesale.com:1433;encrypt=true;databaseName=CDI;user=IICS_SQL;password=IICS_SQL";
        String connectionUrl = "jdbc:sqlserver://LEN23\\MYLOCLEN23:1433;encrypt=true;databaseName=CDI;user=IICS_SQL;password=IICS_SQL";

        try (Connection con = DriverManager.getConnection(connectionUrl); Statement stmt = con.createStatement();) {
            String SQL = "SELECT TOP 10 * FROM Person.Contact";
            ResultSet rs = stmt.executeQuery(SQL);

            // Iterate through the data in the result set and display it.
            while (rs.next()) {
                System.out.println(rs.getString("FirstName") + " " + rs.getString("LastName"));
            }
        }
        // Handle any errors that may have occurred.
        catch (SQLException e) {
            e.printStackTrace();
        }
    }
}