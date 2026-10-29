
NOTE:  CONNECT TO CDI database (or sam_db  in my case)


create table public.employee (
	"employee_id" integer null,
	"employee_name" varchar(50) null,
	"employee_address" varchar(50) null,
	"employee_city" varchar(50) null,
	"employee_state" varchar(50) null,
	"employee_zip_code" integer null,
	"employee_country" varchar(50) null,
	"employee_phone_nmbr" varchar(50) null,
	"employee_fax_nmbr" varchar(50) null,
	"employee_email" varchar(50) null,
	"employee_gender" varchar(50) null,
	"age_group" varchar(50) null,
	"native_lang_desc" varchar(50) null,
	"sec_lang_desc" varchar(50) null,
	"ter_lang_desc" varchar(50) null,
	"position_type" varchar(50) null,
	"dealership_id" integer null,
	"regional_manager" varchar(50) null,
	"dealership_manager" varchar(50) null,
	"hire_date" varchar(50) null,
	"date_entered" varchar(50) null
);

create table public.customer (
	"cust_id" integer null,
	"name" varchar(50) null,
	"address" varchar(50) null,
	"city" varchar(50) null,
	"state" varchar(50) null,
	"postalcode" integer null,
	"country" varchar(50) null,
	"phone" varchar(50) null,
	"last_order_date" varchar(50) null,
	"status" varchar(50) null,
	"tier" integer null,
	"modified_date" varchar(50) null
);

create table public.orders (
	"orderid" integer null,
	"quantity" integer null,
	"customerid" integer null,
	"shipmenttrackingno" varchar(50) null,
	"orderstatus" varchar(50) null,
	"productdescription" varchar(50) null,
	"outletid" integer null,
	"productid" integer null
);


create table public."transaction" (
	"cust_id" integer null,
	"product_id" integer null,
	"dealership_id" integer null,
	"payment_desc" varchar(50) null,
	"promo_id" integer null,
	"date_id" integer null,
	"transaction_id" integer null,
	"employee_id" integer null,
	"time_key" integer null,
	"selling_price" real null,
	"cost" real null,
	"quantity" integer null,
	"discount" real null,
	"holdback" real null,
	"rebate" real null,
	"transaction_date" varchar(50) null
);

create table public.dealership (
	"dealership_id" integer null,
	"dealership_manager_id" integer null,
	"dealership_desc" varchar(50) null,
	"dealership_location" varchar(50) null,
	"dealership_state" varchar(50) null,
	"dealership_region" varchar(50) null,
	"dealership_country" varchar(50) null
);


create table public.sf_account (
	"id" varchar(50) null,
	"name" varchar(50) null,
	"type" varchar(50) null,
	"parentid" varchar(50) null,
	"billingstreet" varchar(128) null,
	"billingcity" varchar(50) null,
	"billingstate" varchar(50) null,
	"billingpostalcode" integer null,
	"billingcountry" varchar(50) null,
	"shippingstreet" varchar(128) null,
	"shippingcity" varchar(50) null,
	"shippingstate" varchar(50) null,
	"shippingpostalcode" integer null,
	"shippingcountry" varchar(50) null,
	"phone" varchar(50) null,
	"website" varchar(50) null,
	"industry" varchar(50) null,
	"numberofemployees" integer null,
	"description" varchar(256) null,
	"createddate" varchar(50) null,
	"createdbyid" varchar(50) null,
	"lastmodifieddate" varchar(50) null,
	"lastmodifiedbyid" varchar(50) null,
	"lastactivitydate" varchar(50) null,
	"annualrevenue" integer null
);




