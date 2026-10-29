
NOTE:  CONNECT TO CDI_STUDENT database (or fitch_db  in my case)

create table public.customer_master (
	"cust_id" integer null,
	"first_name" varchar(50) null,
	"last_name" varchar(50) null,
	"addr1" varchar(50) null,
	"addr2" varchar(50) null,
	"city" varchar(50) null,
	"state" varchar(50) null,
	"postal_code" integer null,
	"phone" integer null,
	"email" varchar(50) null
);

create table public.dim_customer (
	"cust_seq" integer null,
	"cust_id" integer null,
	"first_name" varchar(50) null,
	"last_name" varchar(50) null,
	"addr1" varchar(50) null,
	"addr2" varchar(50) null,
	"city" varchar(50) null,
	"state" varchar(50) null,
	"postal_code" integer null,
	"phone" integer null,
	"email" varchar(50) null,
	"valid_date" varchar(50) null
);

