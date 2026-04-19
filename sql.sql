--dim_currency
create table dwh.dim_currency as(   
select 
	c."date" ::date, -- convert the date column to date type
	c.currency 
from dim_currency c)
;

--Dim_playlist
create table dwh.dim_playlist as(
select 
	p.*,
	p2.trackid,
	p2.last_update as last_update_track -- change the name's column because it is already exists in the other table
from playlist p
left join playlisttrack p2 on p.playlistid =p2.playlistid )
;
--Dim_customer
create table dwh.dim_customer as(
select *
from customer c )
;

-- update the columns to first letter in upper letter
update dwh.dim_customer
set firstname=initcap(firstname)
,lastname=initcap(lastname)
;

--add column 'domain'
alter table dwh.dim_customer
add column domain varchar(100)

update dwh.dim_customer
set domain= substring(email,position('@' in email)+1)
;	


--Dim_employee
create table dwh.dim_employee as (
select
	e.*,
	db.department_name,
	db.budget,
	extract(year from age(now(),e.hiredate)) as years_of_work, -- add a column years of work
	substring(e.email,position('@' in e.email)+1) as domain, -- add a column domain
case -- add a column if the emplyee is manager (1 for Yes , 0 for No or not know)
	when e.employeeid in (select em.reportsto from employee em) then 1
	else 0
end as is_manager
from employee e
left join department_budget db on e.departmentid=db.department_id ) 
;

--Dim_track
-- delete last update columns 
ALTER TABLE stg.album       
Drop column last_update   
;
ALTER TABLE stg.artist       
Drop column last_update   
;
ALTER TABLE stg.mediatype       
Drop column last_update   
;
ALTER TABLE stg.genre    
Drop column last_update   
;


--change the name of name columns according any table  (for the join)
ALTER table stg.track 
rename column name to track_name
;
ALTER table stg.artist  
rename column name to artist_name
;
ALTER table stg.mediatype  
rename column name to mediatype_name
;
ALTER table stg.genre  
rename column name to gener_name
;

create table dwh.dim_track as(
select
	t.trackid,
	t.track_name,
	t.composer,
	t.milliseconds,
	t.bytes,
	t.unitprice,
	t.last_update,
	a.*,
	ar.artist_name,
	m.*,
	g.*
from track t
join album a on a.albumid =t.albumid 
join artist ar on ar.artistid =a.artistid 
join mediatype m on m.mediatypeid=t.mediatypeid 
join genre g on g.genreid =t.genreid )
;
--Change milliseconds to seconds
update dwh.dim_track 
set milliseconds = milliseconds/1000;

ALTER table dwh.dim_track 
rename column milliseconds to seconds;

-- add column mi:ss
ALTER TABLE dwh.dim_track         
add column minute_second varchar(5)  ;

update dwh.dim_track 
set minute_second = to_char(seconds* interval '1 second','MI:SS')
;


--Fact_invoice
--chack if the billingaddress same as the address
select 
c.customerid ,
c.address ,
i.billingaddress 
from customer c
join invoice i on i.customerid =c.customerid
where lower(i.billingaddress) <> lower(c.address)
;
--billingaddress is address  
--so we import the both column 

create table dwh.fact_invoice as(
select *
from invoice i 
)
;

--Fact_invoiceline
create table dwh.fact_invoiceline as(
select 
	i.*,
	i.unitprice * i.quantity as line_total --add column line total
from invoiceline i)
;
-----------
--part 2 אנליזות
--work at dwh schema

--q.1
--מצאו את הפלייליסט עם הכי הרבה שירים , הפלייליסט עם הכי מעט שירים, ואת ממוצע השירים בפלייליסט
with amount_track as (
	select 
		playlistid ,
		count(trackid) as track_per_playlist
	from dim_playlist p
	group by playlistid),
track_table as(
select
	a.*,
	max(track_per_playlist) over() as max_track,
	min(track_per_playlist) over() as min_track,
	avg(track_per_playlist) over() as avg_track
from amount_track a)
select
	playlistid,
	track_per_playlist,
	avg_track
from track_table t
where 
	t.track_per_playlist =max_track or
	t.track_per_playlist=min_track
order by track_per_playlist desc
;

--q2
with trackid_sales as(
	select 
		t.trackid,
		count(fi.line_total) as count_sales
	from dim_track t
	left join fact_invoiceline fi on t.trackid=fi.trackid
	group by t.trackid),
group_sales_table as(
select 
	t.*,
case 
	when count_sales=0 then '0'
	when count_sales>=1 and count_sales<5 then '1<5'
	when count_sales>=5 and count_sales<=10 then '5-10'
	else '10'
end as groups_sales
from trackid_sales t)
select
	groups_sales,	
	count(trackid) as count_per_group
from group_sales_table g
group by groups_sales
order by groups_sales
;

--q3
--הציגו סכום מכירות לפי מדינה עבור 5 המדינות עם הסכום הגבוה ביותר ו5- המדינות עם
--הסכום הנמוך ביותר. 
with sales as(
	select 
		c.country ,
		sum(f.total) as total_sales
	from dim_customer c
	left join fact_invoice f on f.customerid =c.customerid 
	group by 1),
ranking as
(select 
	s.*,
	rank() over(order by s.total_sales asc) as asc_rank,
	rank() over(order by s.total_sales desc) as desc_rank
from sales s)
select 
 	r.*
from ranking r
where r.asc_rank <=5 or r.desc_rank<=5
;

--(עבור כל מדינה מסעיף א', מהו אחוז המכירות של כל ז'אנר מתוך סך המכירות (סכום
--במדינה? הוסיפו דירוג לפי אחוז המכירות
with country_gener_table as(
		select
			part1.country,
			part1.total_sales,
			t.gener_name,
			sum(il.line_total) over(partition by part1.country,t.gener_name) as sales_per_gener
		from 
			(with sales as(
				select 
					c.country ,
					sum(f.total) as total_sales
				from dim_customer c
				left join fact_invoice f on f.customerid =c.customerid 
				group by 1),
			ranking as
			(select 
				s.*,
				rank() over(order by s.total_sales asc) as asc_rank,
				rank() over(order by s.total_sales desc) as desc_rank
			from sales s)
			select 
			 	r.*
			from ranking r
			where r.asc_rank <=5 or r.desc_rank<=5)
			as part1
		left join dim_customer c on part1.country=c.country
		left join fact_invoice f on f.customerid =c.customerid 
		left join fact_invoiceline il on f.invoiceid=il.invoiceid 
		left join dim_track t on t.trackid=il.trackid),
precent as(
		select distinct 
			c.*,
			round(c.sales_per_gener/total_sales,2) as sales_gener_precent
		from country_gener_table c)
select
	p.*,
	dense_rank() over(partition by country order by sales_gener_precent desc)
from precent p
;

--q.4
-- נתחו את הפרמטרים הבאים עבור כל מדינה: מספר הלקוחות שיש בה, כמות הזמנות ממוצעת
--מכל לקוח וסכום הכנסות ממוצע מכל לקוח. מכיוון שיש מדינות עם לקוח אחד בלבד, קבצו את
--"Other" הלקוחות הללו תחת
with customer_per_country as
	(select 
		c.country ,
		c.customerid,
		count(c.customerid) over(partition by c.country) as amount_cust
	from dim_customer c)
,other_table as(
	select 
	c.country ,
	c.customerid,
	case 
		when c.amount_cust<=1 then 'Other'
		else country
	end countries,
	c.amount_cust
	from customer_per_country c),
relevent_table as(
	select distinct
		o.customerid,
		o.countries,
		sum(o.amount_cust) over(partition by o.countries) as new_total_customer
	from other_table o),
orders_income as(
	select distinct 
		r.countries,
		r.new_total_customer,
		count(i.invoiceid) over(partition by r.countries) as orders_per_country,
		sum(i.total) over(partition by r.countries) as income_per_country
	from relevent_table r
	left join fact_invoice i on i.customerid= r.customerid)
select 
	o.countries,
	o.new_total_customer,
	round(o.orders_per_country/new_total_customer,2) as avg_order_quantity,
	round(o.income_per_country/new_total_customer,2) as avg_income
from orders_income o
;

--q.5
--נתחו את הפרמטרים הבאים עבור כל עובד: שנות ותק, מספר הלקוחות שטיפל בהם בכל שנה
--ואחוז גדילה של סכום המכירות שלו בכל שנה ביחס לשנה הקודמת 
with detail_table as(
	select 
		e.employeeid,
		e.years_of_work,
		extract (year from i.invoicedate) as order_year,
		count(c.customerid) as customer_amount,
		sum(i.total) as sales
	from dim_employee e
	left join dim_customer c on c.supportrepid=e.employeeid 
	left join fact_invoice i on i.customerid=c.customerid 
	group by e.employeeid,e.years_of_work,extract (year from i.invoicedate)
	order by e.employeeid,extract (year from i.invoicedate)),
lasy_year_table as(
	select 
		d.*,
		lag(sales,1,sales) over(partition by employeeid order by order_year) as lag
	from detail_table d)
select
	l.*,
	round((l.sales/l.lag)-1,2) as sales_growth
from lasy_year_table l
;

--q6 אנליזה נוספת מעצמנו
--2שירים הכי נמכרים בכל ג'אנר 
with relative_table as(
	select 
		t.gener_name,
		t.trackid,
		t.track_name,
		il.line_total as totals 
	from dim_track t
	join fact_invoiceline il on t.trackid=il.trackid ),
quantity_amount_gener as(
	select 
		r.gener_name,
		r.trackid,
		r.track_name,
		count(r.trackid)as quantity_per_gener_track,
		sum(r.totals) as amount_per_gener_track
	from relative_table r
	group by gener_name,trackid,r.track_name),
ranking_table as
	(select distinct 
		q.*,
		row_number() over(partition by gener_name order by quantity_per_gener_track desc) as ranking_quantity, --A setting that will choose randomly
		row_number() over(partition by gener_name order by amount_per_gener_track desc) as ranking_amount --A setting that will choose randomly
	from quantity_amount_gener q)
select 
	r.gener_name,
	r.track_name,
	r.quantity_per_gener_track,
	r.amount_per_gener_track,
	r.ranking_quantity,
	r.ranking_amount
from ranking_table r
where r.ranking_quantity<=2 or r.ranking_amount<=2
order by r.gener_name,ranking_quantity,ranking_amount
;
