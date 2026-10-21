# Code noise reduction
 snippets and patterns of noise
 
 ## clean up of mock data
no need to clean up the mock data by ranges etc, we will leave it to the user to clean the mock data for each runs manually
therefore remove this code pattern through out the code base
tables.deleteRange("V_ECI_ETL_SRC_FAMILY_ADDRESS", "ID", ID, ID + 999_999); 

## Need tutoring on
How the below works, explain like I am a junior developer
- public String fillMockAll(List<String> mappings)
