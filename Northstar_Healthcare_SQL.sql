SELECT *
FROM appointments;

-- First we create a staging or copy of the raw dataset
CREATE TABLE apps
LIKE appointments;

INSERT INTO apps
SELECT *
FROM appointments;

-- Row_number assigns a unique Interger or row number to each row within a partition.
-- In this case since we are partitioning by a value the is unique to each column, appointment_id,
-- Then whenever the row number is > 1 it should be a duplicate
-- We still need to check where we can to verify the it is a duplicate

SELECT *, row_number() OVER (PARTITION BY appointment_id)
FROM apps
WHERE row_num > 1;

ALTER TABLE apps
ADD column row_num INT;

INSERT INTO apps
SELECT *, row_number() OVER (PARTITION BY appointment_id)
FROM appointments;

SELECT * 
FROM apps
WHERE 'row_num' > 1;

ALTER TABLE apps
DROP COLUMN row_num;

-- Since there appear to be no duplicates, we can move on
-- Note: we didn't have to create a new column and could had used a CTE
-- to check for it. Out of habit I forgot to check this first.

-- Next I will be checking whether certain id fields match the exact count in excel.
-- This is just a way to make sure we don't have any new or special fields.

SELECT COUNT(DISTINCT provider_id), COUNT(DISTINCT clinic_id), COUNT(DISTINCT department_id)
FROM apps;

-- Numbers match. There should be 30 provider ids, 8 different clinic ids, and 5 department ids
-- Lastly I will change the data type to prevent any issues later on.
-- In this data set we only need to change two columns.

ALTER TABLE apps
MODIFY appointment_date DATE, 
MODIFY scheduled_date DATE;


-- 1. Which clinics and departments have the longest patient wait times, and how do waits vary by appointment type

SELECT * 
FROM apps;

-- Clinic and department breakdown
SELECT clinic_id,
	department_id,
	ROUND(AVG(wait_days), 2) as Wait_days,
    COUNT(appointment_id) as Appointments
FROM apps
GROUP BY clinic_id, department_id
ORDER BY Wait_days desc;

-- Just for clinic_id
SELECT clinic_id,
	ROUND(AVG(wait_days), 2) as Wait_days,
    COUNT(appointment_id) as Appointments
FROM apps
GROUP BY clinic_id
ORDER BY Wait_days desc;

-- Just for Department_id
SELECT department_id,
	ROUND(AVG(wait_days), 2) as Wait_days,
    COUNT(appointment_id) as Appointments
FROM apps
GROUP BY department_id
ORDER BY Wait_days desc;

-- Comparison with appointment type
SELECT appointment_type, ROUND(AVG(wait_days), 2) as Wait_days
FROM apps
GROUP BY appointment_type
ORDER BY Wait_days desc;


-- 2. Which clinics and departments have the highest cancellation and no-show rates?

SELECT * 
FROM apps;

-- For clinics
WITH ns AS (SELECT clinic_id, COUNT(*) as 'No_show_appointments'
	FROM apps
	WHERE appointment_status = 'No-show'
	GROUP BY clinic_id
)
SELECT a.clinic_id,
		COUNT(*) as 'Cancelled_appointments',
		ns.no_show_appointments
FROM apps as a
LEFT JOIN ns
	ON a.clinic_id = ns.clinic_id
WHERE a.appointment_status = 'Cancelled'
GROUP BY a.clinic_id, ns.no_show_appointments;


-- For Deparments
WITH ns AS (SELECT department_id, COUNT(*) as 'No_show_appointments'
	FROM apps
	WHERE appointment_status = 'No-show'
	GROUP BY department_id
)
SELECT a.department_id,
		COUNT(*) as 'Cancelled_appointments',
		ns.no_show_appointments
FROM apps as a
LEFT JOIN ns
	ON a.department_id = ns.department_id
WHERE a.appointment_status = 'Cancelled'
GROUP BY a.department_id, ns.no_show_appointments
ORDER BY Cancelled_appointments desc,no_show_appointments desc;

-- Both
WITH ns AS (SELECT clinic_id, COUNT(*) as 'No_show_appointments'
	FROM apps
	WHERE appointment_status = 'No-show'
	GROUP BY clinic_id
)
SELECT a.clinic_id, a.department_id,
		COUNT(*) as 'Cancelled_appointments',
		ns.no_show_appointments
FROM apps as a
LEFT JOIN ns
	ON a.clinic_id = ns.clinic_id
WHERE a.appointment_status = 'Cancelled'
GROUP BY a.clinic_id, a.department_id, ns.no_show_appointments
ORDER BY Cancelled_appointments desc,no_show_appointments desc;

-- amnount of uncomplete appointments
-- These are all the appointment the resulted in no-show or cancellations.

SELECT clinic_id, department_id, COUNT(*) as Unconmplete_apps
FROM apps
WHERE appointment_status IN ('Cancelled', 'no-show')
GROUP BY clinic_id, department_id
ORDER BY Unconmplete_apps desc;

SELECT clinic_id, COUNT(*) as Unconmplete_apps
FROM apps
WHERE appointment_status IN ('Cancelled', 'no-show')
GROUP BY clinic_id
ORDER BY Unconmplete_apps desc;

SELECT  department_id, COUNT(*) as total_appointmets
FROM apps
GROUP BY  department_id
ORDER BY total_appointmets desc;

SELECT  clinic_id, COUNT(*) as total_appointmets
FROM apps
GROUP BY  clinic_id
ORDER BY total_appointmets desc;


-- 3.Are clinics using their available and staffed capacity effectively, or are there staffing and scheduling inefficiencies?

-- I had to import more data. This one is already cleaned from excel, but we need to change the data type of one column
-- and create a copy so we don't work dirrectly on raw data.

SELECT * 
FROM monthly_capacity;

CREATE TABLE mcap
LIKE monthly_capacity;

INSERT mcap
SELECT *
FROM monthly_capacity;

ALTER TABLE mcap
MODIFY month_start DATE;

SELECT *
FROM mcap; 

-- first off, we need to define what a effectively staffed capacity means
-- for the sake of this project we will look at the percent_in_use column
-- the I had already calculated through the use of excel.
-- essentially it tells use what percent of the capacity a clinic and department are using.
-- We can create different bands using case statements

SELECT clinic_id, Department_id, ROUND(AVG(percent_in_use), 2) as Avg_cap,
	CASE
		WHEN AVG(percent_in_use) > 0.89 THEN 'Perfect'
        WHEN AVG(percent_in_use) > 0.84 THEN 'Good'
         -- WHEN AVG(percent_in_use) > 0.79 THEN 'Needs_Improvement'
         ELSE 'Needs_Improvement'
	END as Cap_status
FROM mcap
GROUP BY clinic_id, department_id;

-- We can use a cte as well to count the amount of clinics and departments 
-- the fall under the different bands:

With cs AS (
	SELECT clinic_id, Department_id, ROUND(AVG(percent_in_use), 2) as Avg_cap,
		CASE
			WHEN AVG(percent_in_use) > 0.89 THEN 'Perfect'
			WHEN AVG(percent_in_use) > 0.84 THEN 'Good'
			-- WHEN AVG(percent_in_use) > 0.79 THEN 'Needs_Improvement'
			ELSE 'Needs_Improvement'
	END as Cap_status
FROM mcap
GROUP BY clinic_id, department_id
)
SELECT Cap_status, 
	COUNT(Cap_status)
FROM cs
	GROUP BY Cap_status;

-- There are some things to note. Not every clinic and department will have the same number of open positions 
-- and not every clinic and department has the same capacity
-- For this reason I chose to look at the amount of staff capacity being used by comparing it to its own capacity
-- rather than just saying a place with 9 openings and 100 total capacity performs better than a place with 14 openings
-- and a total capacity of 120. 

-- 4. Which clinics and departments perform best and worst financially based on charges, reimbursements, direct costs, and operating expenses?
-- Now first we need to define how this will be measured. does the best performing clinic and department have the highest revenue or the highest profit?
-- For this project I will use both metrics, but there are also many factor like total expenses, total amount of reimbursements, or even
-- the foot trafic the clinic or department goes through. For the sake of this project I will only use revenue and profit, but the best
-- financially performing clinic and department is subjective to how best or worst is being defined
-- Now I am going off the assumption Total_charge_amount means revenue

SELECT *
FROM apps;

SELECT clinic_id, department_id, 
	ROUND(SUM(charge_amount), 2) as Total_charge_amount,
    ROUND(SUM(reimbursement_amount), 2) as Total_reimbursement_amount,
    ROUND(SUM(estimated_direct_cost), 2) as Total_estimated_direct_cost
FROM apps
GROUP BY clinic_id, department_id
ORDER BY Total_charge_amount;

-- We can use monthly_expenses table to pull the rest of the information.
-- Since the data was already cleaned, I will move on to chaning the data type for one column
-- and creating a copy so we are not working on raw data.

SELECT *
FROM monthly_expenses;

CREATE TABLE mexp
LIKE monthly_expenses;

INSERT mexp
SELECT *
FROM monthly_expenses;

SELECT *
FROM mexp;

-- We can use the total_expenses column to make the query simpler to read.
SELECT clinic_id, department_id, 
	ROUND(SUM(charge_amount), 2) as Total_charge_amount,
    ROUND(SUM(reimbursement_amount), 2) as Total_reimbursement_amount,
    ROUND(SUM(estimated_direct_cost), 2) as Total_estimated_direct_cost
    FROM apps
GROUP BY clinic_id, department_id
ORDER BY Total_charge_amount
;

-- With total expenses included under one table
-- But there is one slight issue:
SELECT
	me.clinic_id,
    ac.department_id,
    ROUND(SUM(ac.charge_amount), 2) as Total_charge_amount,
    ROUND(SUM(ac.reimbursement_amount), 2) as Total_reimbursement_amount,
    ROUND(SUM(ac.estimated_direct_cost), 2) as Total_estimated_direct_cost,
    ROUND(SUM(me.total_expenses), 2) as Total_expenses
FROM mexp as me
	LEFT JOIN apps as ac
    ON me.clinic_id = ac.clinic_id
    AND me.department_id = ac.department_id
GROUP BY me.clinic_id, ac.department_id
ORDER BY total_charge_amount desc, Total_expenses desc;

-- mexp table filters the expenses on a monthly basis while apps doesn't
-- Essentially, to make it work we need to account for the months 
-- This could be done easily in excel, but to keep this project easier
-- I will use a separate query for it.

SELECT clinic_id, 
	department_id, 
	ROUND(SUM(charge_amount), 2) as Total_charge_amount,
    ROUND(SUM(reimbursement_amount), 2) as Total_reimbursement_amount,
    ROUND(SUM(estimated_direct_cost), 2) as Total_estimated_direct_cost
    FROM apps
GROUP BY clinic_id
,department_id
ORDER BY Total_charge_amount desc
;

SELECT clinic_id,
		-- department_id,
       ROUND(SUM(total_expenses), 2) AS Total_expenses,
		ROUND(SUM(labor_expense), 2) AS labor_expense,
		ROUND(SUM(other_operating_expense), 2) AS other_operating_expense
FROM mexp
GROUP BY clinic_id 
	-- ,department_id
ORDER BY Total_Expenses desc;

SELECT *
FROM mexp;

SELECT *
FROM apps;

SELECT *
FROM mcap;