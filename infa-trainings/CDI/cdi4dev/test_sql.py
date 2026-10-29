import pyodbc

# Database connection details
server = 'LEN23\\MYLOCLEN23'  # Change if your SQL Server instance is different
database = 'CDI'  # Replace with your database name
username = 'IICS_SQL'  # Replace with your username
password = 'IICS_SQL'  # Replace with your password

# Connection string
conn_str = (
    f'DRIVER={{SQL Server}};'
    f'SERVER={server};'
    f'DATABASE={database};'
    f'UID={username};'
    f'PWD={password};'
    f'Trusted_Connection=no;'
)

try:
    # Establish connection
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    
    # Execute query
    cursor.execute("SELECT count(1) FROM [CDI].[dbo].[TRANSACTION]")
    row_count = cursor.fetchone()[0]
    
    # Print result
    print(f"Total employees: {row_count}")
    
    # Close connection
    cursor.close()
    conn.close()

except Exception as e:
    print("Error:", e)