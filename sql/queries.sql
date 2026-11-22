SELECT *
FROM bronze.iowa_businesses_raw;

SELECT column_name
FROM information_schema.columns
WHERE table_name = 'iowa_businesses_raw'
  AND table_schema = 'bronze'
ORDER BY ordinal_position;

SELECT
    effective_date,
    TO_DATE(effective_date, 'YYYY-MM-DD') AS date_fix
FROM bronze.iowa_businesses_raw; -- change effective_date col to date

SELECT DISTINCT corporation_type, 
	TRIM(corporation_type) AS trimmed_corporation_type
FROM bronze.iowa_businesses_raw; -- trim

SELECT DISTINCT corporation_type, 
	COUNT(*) AS count_corporation_type
FROM bronze.iowa_businesses_raw
GROUP BY corporation_type;

SELECT legal_name, UPPER(TRIM(legal_name)) AS trimmed_legal_name
FROM bronze.iowa_businesses_raw; -- trim

SELECT registered_agent, UPPER(TRIM(registered_agent)) AS trimmed_registered_agent
FROM bronze.iowa_businesses_raw; -- trim

SELECT legal_name, REPLACE(legal_name, '"', '') AS trimmed_legal_name
FROM bronze.iowa_businesses_raw
WHERE legal_name LIKE '"%' OR legal_name LIKE '%"' OR legal_name LIKE '"%"'; -- remove quotes, 102 rows out of 350k

SELECT ra_address_1, REPLACE(ra_address_1, '"', '') AS ra_1_cleaned
FROM bronze.iowa_businesses_raw
WHERE ra_address_1 LIKE '"%' OR ra_address_1 LIKE '%"' OR ra_address_1 LIKE '"%"'; -- remove quotes, 2 rows


SELECT ho_city, REPLACE(ho_city, '"', '') AS ho_city_cleaned
FROM bronze.iowa_businesses_raw
WHERE ho_city LIKE '"%' OR ho_city LIKE '%"' OR ho_city LIKE '"%"'; -- remove quotes, 1 row


SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_address_1 ~ '^[0-9]+$'; -- only numbers in ra_address_1(54 rows): remove/keep(tbd)


SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_city ~ '^[0-9]+$'; -- only numbers in ra_city, 12 rows. some numbers(most) correspond with ra_zip


SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_state ~ '^[A-Za-z]{3,}$'; -- no ra_state has three or more letters

SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_state ~ '^[0-9]+$'; -- no ra_state has numbers

SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_city ~ '^[A-Za-z]{2}$'; -- ra_city could be city names since LE, CL and DA are abbrs for cities

SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_zip ~ '^[A-Za-z]'; -- no ra_zip contains letters

SELECT ra_address_1, ra_city, ra_zip, ra_state
FROM bronze.iowa_businesses_raw
WHERE ra_zip ~ '^[0-9]{1,4}$'; -- ra_zip contains zip codes with nums <= 4

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_address_1 ~ '^[0-9]+$'; -- ho_address_1 has 187 entries which are only numbers

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_city ~ '^[0-9]+$';

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_state ~ '^[A-Za-z]{3,}$'; -- no ho_state has >= 3 letters

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_state ~ '^[0-9]+$'; -- no ho_state has numerical entries

SELECT ho_address_1, ho_city, ho_zip, ho_state, ho_country
FROM bronze.iowa_businesses_raw
WHERE ho_city ~ '^[A-Za-z]{2}$'; -- 25 rows have shortened city names

SELECT *
FROM (
    SELECT *,
        COUNT(*) OVER (
            PARTITION BY corp_number, legal_name, corporation_type, effective_date, registered_agent,
				ra_address_1, ra_city, ra_state, ra_zip, ra_latitude, ra_longitude, ra_location,
				ho_address_1, ho_city, ho_state, ho_zip, ho_country, ho_latitude, ho_longitude, ho_location
        ) AS duplicate_count
    FROM bronze.iowa_businesses_raw
) AS duplicates
WHERE duplicate_count > 1; -- no duplicates