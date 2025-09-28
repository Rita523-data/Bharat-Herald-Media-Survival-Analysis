-- What is the trend in copies printed, copies sold, and net circulation across all 
-- cities from 2019 to 2024? How has this changed year-over-year? 

select ps.year,c.city,
	sum(copies_sold) as total_sold,
	sum(Net_circulation) as total_net 
from fact_print_sales ps 
join dim_city c
group by ps.year,c.city
order by ps.year ;



 -- Which cities contributed the highest to net circulation and copies sold in 2024? Are 
-- these cities still profitable to operate in? 

select c.city , 
	sum(p.copies_sold) as copies_sold_2024 , 
	sum(p.net_circulation ) as net_circulation_2024
from dim_city c 
join fact_print_sales p 
on c.city_id = p.City_ID
where p.year = "2024"
group by city
order by net_circulation_2024 desc ;



-- Which cities have the largest gap between copies printed and net circulation, and 
-- how has that gap changed over time? 

select p.year,c.city,
	sum(p.copies_sold) as Total_copies_sold,
	sum(p.net_circulation) as Total_net,
	(sum(p.Copies_Sold)-sum(p.Net_Circulation)) as gap,
	round((sum(p.copies_returned)/sum(p.copies_sold))*100,2) as gap_pct
from fact_print_sales p 
join dim_city c 
on p.City_ID = c.city_id
group by c.city,p.year
order by year asc;

-- . Ad Revenue Trends by Category 
 -- How has ad revenue evolved across different ad categories between 2019 and 
-- 2024? Which categories have remained strong, and which have declined? 

select r.year,r.ad_category,c.standard_ad_category,
round(sum(ad_revenue_inr),2) as total_ad_revenue
from dim_ad_category1 c 
join fact_ad_revenue r 
on c.ad_category_id = r.ad_category
where r.year between "2019" and "2024"
group by r.year,r.ad_category,c.standard_ad_category
order by r.year ,total_ad_revenue desc ;

-- 5. City-Level Ad Revenue Performance 
 --  Which cities generated the most ad revenue, and how does that correlate with their 
-- print circulation? 

select c.city,
round(sum(r.ad_revenue_inr),2) as total_ad_revenue,
sum(p.net_circulation) as total_net_circulation
from dim_city c 
join fact_print_sales p 
on c.city_id = p.City_ID
join fact_ad_revenue r 
on r.edition_id = p.edition_ID
group by c.city 
order by total_ad_revenue desc;

-- 6. Digital Readiness vs. Performance 
  -- Which cities show high digital readiness (based on smartphone, internet, and 
-- literacy rates) but had low digital pilot engagement?

WITH readiness AS (
    SELECT 
        c.city,
        fcr.city_id,
        AVG(fcr.smartphone_penetration) AS avg_smartphone,
        AVG(fcr.internet_penetration) AS avg_internet,
        AVG(fcr.literacy_rate) AS avg_literacy,
        round((AVG(fcr.smartphone_penetration) + 
         AVG(fcr.internet_penetration) + 
         AVG(fcr.literacy_rate)) / 3,2) AS readiness_score
    FROM fact_city_readiness fcr
    JOIN dim_city c ON fcr.city_id = c.city_id
    WHERE fcr.year = "2021"
    GROUP BY c.city, fcr.city_id
),
engagement AS (
    SELECT 
        c.city,
        round(sum(fp.downloads_or_accesses)/sum(fp.users_reached)*100,2) AS engagement_rate_pct
    FROM fact_digital_pilot fp
    JOIN dim_city c ON fp.city_id = c.city_id
    WHERE fp.launch_month LIKE '2021%'
    GROUP BY c.city
)
SELECT 
    r.city,
    r.readiness_score,
    e.engagement_rate_pct
FROM readiness r
JOIN engagement e 
    ON r.city = e.city
ORDER BY r.readiness_score DESC, e.engagement_rate_pct ASC;

-- 7. Ad Revenue vs. Circulation ROI 
  -- Which cities had the highest ad revenue per net circulated copy? Is this ratio 
-- improving or worsening over time? 

with cte as (select r.year,c.city,
round(sum(r.ad_revenue_inr)/nullif(sum(p.net_circulation),0),2) as Circulation_ROI
from fact_ad_revenue r 
join fact_print_sales p 
on r.edition_id = p.edition_ID
join dim_city c 
on c.city_id = p.City_ID
group by c.city,r.year
order by r.year,Circulation_ROI desc 
)
SELECT 
    city,
    year,
    Circulation_ROI,
    round(LAG(Circulation_ROI) OVER (PARTITION BY city ORDER BY year),2) AS prev_year_roi,
    CASE 
        WHEN LAG(Circulation_ROI) OVER (PARTITION BY city ORDER BY year) IS NULL THEN 'N/A'
        WHEN Circulation_ROI > LAG(Circulation_ROI) OVER (PARTITION BY city ORDER BY year) THEN 'Improving'
        ELSE 'Worsening'
    END AS roi_trend
FROM cte
ORDER BY city, year;


-- 8. Digital Relaunch City Prioritization 
 -- Based on digital readiness, pilot engagement, and print decline, which 3 cities should be 
-- prioritized for Phase 1 of the digital relaunch?

WITH readiness_2021 AS (
  SELECT
    c.city_id,
    c.city AS city_name,
    AVG(fcr.literacy_rate)       AS avg_literacy,
    AVG(fcr.smartphone_penetration) AS avg_smartphone,
    AVG(fcr.internet_penetration) AS avg_internet,
    (AVG(fcr.literacy_rate) + AVG(fcr.smartphone_penetration) + AVG(fcr.internet_penetration)) / 3.0 AS readiness_score
  FROM fact_city_readiness fcr
  JOIN dim_city c ON fcr.city_id = c.city_id
  WHERE fcr.Year = "2021"
  GROUP BY c.city_id, c.city
),
engagement_2021 AS (
  SELECT
    c.city_id,
    c.city AS city_name,
    SUM(fp.users_reached) AS users_reached,
    SUM(fp.downloads_or_accesses) AS downloads_or_accesses,
 
    100.0 * SUM(fp.downloads_or_accesses) / NULLIF(SUM(fp.users_reached),0) AS engagement_rate_pct
  FROM fact_digital_pilot fp
  JOIN dim_city c ON fp.city_id = c.city_id
  WHERE fp.launch_month LIKE '2021%'     
  GROUP BY c.city_id, c.city
),
circulation_2019_2024 AS (
  SELECT
    c.city_id,
    c.city AS city_name,
    SUM(CASE WHEN fps.Year = '2019' THEN fps.net_circulation ELSE 0 END) AS net_circ_2019,
    SUM(CASE WHEN fps.Year = '2024' THEN fps.net_circulation ELSE 0 END) AS net_circ_2024
  FROM fact_print_sales fps
  JOIN dim_city c ON fps.city_id = c.city_id
  WHERE fps.Year IN ('2019', '2024')
  GROUP BY c.city_id, c.city
)
SELECT
  r.city_id,
  r.city_name,
ROUND(r.readiness_score, 2) AS readiness_score,
ROUND(COALESCE(e.engagement_rate_pct, 0), 2) AS engagement_rate_pct,
ROUND(
    CASE
      WHEN c.net_circ_2019 > 0
        THEN 100.0 * (c.net_circ_2019 - c.net_circ_2024) / c.net_circ_2019
      ELSE NULL
    END, 2
  ) AS print_decline_pct,
  ROUND(
    (
      COALESCE(r.readiness_score,0)
      + COALESCE(
          CASE WHEN c.net_circ_2019 > 0
            THEN 100.0 * (c.net_circ_2019 - c.net_circ_2024) / c.net_circ_2019
            ELSE 0 END
        ,0) 
      + (100.0 - COALESCE(e.engagement_rate_pct,0)) 
    )/3, 2
  ) AS priority_score
FROM readiness_2021 r
LEFT JOIN engagement_2021 e ON r.city_id = e.city_id
LEFT JOIN circulation_2019_2024 c ON r.city_id = c.city_id
WHERE r.readiness_score IS NOT NULL
ORDER BY priority_score DESC
LIMIT 3;


