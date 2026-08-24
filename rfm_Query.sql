USE ecommerce_analytics;

-- Quick check: how many customers are in the RFM dataset?
SELECT COUNT(*) AS total_customers
FROM rfm_analysis;

-- Take a quick look at the data
SELECT *
FROM rfm_analysis
LIMIT 20;

-- CustomerID uniquely identifies each customer
ALTER TABLE rfm_analysis
ADD PRIMARY KEY (CustomerID);

-- Review the table structure
DESCRIBE rfm_analysis;

-- See how customers are distributed across RFM segments
SELECT 
    COUNT(CustomerID) AS customer_count,
    Segment
FROM rfm_analysis
GROUP BY Segment;


-- ============================================================
-- Customer Segment Overview
-- Understand how each segment contributes to the customer base
-- and overall revenue.
-- ============================================================

SELECT 
    Segment,
    COUNT(*) AS customer_count,
    ROUND(
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM rfm_analysis), 
        2
    ) AS pct_of_customers,
    ROUND(SUM(Monetary), 2) AS total_revenue,
    ROUND(
        SUM(Monetary) * 100.0 / 
        (SELECT SUM(Monetary) FROM rfm_analysis), 
        2
    ) AS pct_of_revenue,
    ROUND(AVG(Monetary), 2) AS avg_customer_value
FROM rfm_analysis
GROUP BY Segment
ORDER BY total_revenue DESC;


-- ============================================================
-- Champions
-- Identify our highest-value customers for retention and rewards.
-- ============================================================

SELECT 
    CustomerID,
    Recency AS days_since_last_purchase,
    Frequency AS total_purchases,
    ROUND(Monetary, 2) AS lifetime_value,
    ROUND(Monetary / Frequency, 2) AS avg_order_value,
    RFM_Score
FROM rfm_analysis
WHERE Segment = 'Champions'
ORDER BY Monetary DESC
LIMIT 50;


-- ============================================================
-- At-Risk Customers
-- Find high-value customers who haven't purchased recently.
-- These customers represent potential revenue at risk.
-- ============================================================

SELECT 
    CustomerID,
    Recency AS days_since_last_purchase,
    Frequency AS past_purchases,
    ROUND(Monetary, 2) AS lifetime_value,
    ROUND(Monetary / Frequency, 2) AS historical_avg_order,
    RFM_Score,
    CONCAT('$', ROUND(Monetary, 2), ' at risk') AS revenue_at_risk
FROM rfm_analysis
WHERE Segment = 'At Risk'
ORDER BY Monetary DESC
LIMIT 50;


-- ============================================================
-- Pareto Analysis
-- Check whether a small percentage of customers generates
-- most of the company's revenue.
-- ============================================================

WITH ranked_customers AS (
    SELECT 
        CustomerID,
        ROUND(Monetary, 2) AS lifetime_value,
        
        -- Running revenue total from highest-value customers downward
        SUM(Monetary) OVER (
            ORDER BY Monetary DESC
        ) AS running_total,
        
        -- Total revenue across all customers
        SUM(Monetary) OVER () AS total_revenue,
        
        -- Rank customers by lifetime value
        ROW_NUMBER() OVER (
            ORDER BY Monetary DESC
        ) AS customer_rank
        
    FROM rfm_analysis
),

total_count AS (
    SELECT COUNT(*) AS total_customers
    FROM rfm_analysis
)

SELECT 
    customer_rank,
    CustomerID,
    lifetime_value,
    ROUND(running_total, 2) AS cumulative_revenue,
    CONCAT(
        ROUND(customer_rank * 100.0 / total_customers, 2), 
        '%'
    ) AS pct_of_customers,
    CONCAT(
        ROUND(running_total * 100.0 / total_revenue, 2), 
        '%'
    ) AS pct_of_revenue
FROM ranked_customers
CROSS JOIN total_count
WHERE running_total * 100.0 / total_revenue >= 80.0
ORDER BY customer_rank
LIMIT 1;


-- ============================================================
-- Segment Summary View
-- Create a clean summary table that can be connected directly
-- to Power BI for dashboard reporting.
-- ============================================================

CREATE OR REPLACE VIEW vw_segment_summary AS
SELECT 
    Segment,
    COUNT(*) AS customer_count,
    
    ROUND(
        COUNT(*) * 100.0 / 
        (SELECT COUNT(*) FROM rfm_analysis), 
        2
    ) AS pct_of_customers,
    
    ROUND(SUM(Monetary), 2) AS total_revenue,
    
    ROUND(
        SUM(Monetary) * 100.0 / 
        (SELECT SUM(Monetary) FROM rfm_analysis), 
        2
    ) AS pct_of_revenue,
    
    ROUND(AVG(Monetary), 2) AS avg_customer_value,
    ROUND(AVG(Recency), 1) AS avg_recency,
    ROUND(AVG(Frequency), 1) AS avg_frequency,
    ROUND(MIN(Monetary), 2) AS min_value,
    ROUND(MAX(Monetary), 2) AS max_value

FROM rfm_analysis
GROUP BY Segment
ORDER BY total_revenue DESC;

-- Quick check of the segment summary
SELECT *
FROM vw_segment_summary;


-- ============================================================
-- Customer Detail View
-- Add business recommendations to each customer's RFM profile.
-- This makes the dataset easier to use for targeted marketing.
-- ============================================================

CREATE OR REPLACE VIEW vw_customer_details AS
SELECT 
    CustomerID,
    Segment,
    Recency,
    Frequency,
    ROUND(Monetary, 2) AS lifetime_value,
    ROUND(Monetary / Frequency, 2) AS avg_order_value,
    R_Score,
    F_Score,
    M_Score,
    RFM_Score,

    -- Recommended action based on customer segment
    CASE 
        WHEN Segment IN ('Champions', 'Loyal Customers') 
            THEN 'Retain & Reward'
            
        WHEN Segment IN ('At Risk', 'Can''t Lose Them') 
            THEN 'Win Back - Urgent'
            
        WHEN Segment = 'New Customers' 
            THEN 'Nurture & Onboard'
            
        WHEN Segment IN ('Lost', 'Hibernating') 
            THEN 'Reactivation Campaign'
            
        WHEN Segment = 'Potential Loyalists' 
            THEN 'Build Relationship'
            
        WHEN Segment = 'About to Sleep' 
            THEN 'Re-engage'
            
        ELSE 'Monitor'
    END AS recommended_action,

    -- Group customers into value tiers based on lifetime value
    CASE
        WHEN Monetary >= 10000 
            THEN 'Tier 1: Ultra-VIP'
            
        WHEN Monetary >= 1000 
            THEN 'Tier 2: VIP'
            
        WHEN Monetary >= 500 
            THEN 'Tier 3: Premium'
            
        ELSE 'Tier 4: Standard'
    END AS value_tier

FROM rfm_analysis;


-- Quick check of the customer-level view
SELECT *
FROM vw_customer_details
LIMIT 10;


-- ============================================================
-- Marketing Priority List
-- Turn RFM segments into actionable customer groups and
-- recommended marketing campaigns.
-- ============================================================

CREATE OR REPLACE VIEW vw_action_priority AS
SELECT 
    CustomerID,
    Segment,
    ROUND(Monetary, 2) AS lifetime_value,
    Recency AS days_inactive,
    Frequency AS total_orders,

    -- Lower priority number = more urgent
    CASE 
        WHEN Segment = 'Champions' AND Monetary > 10000 THEN 1
        WHEN Segment = 'At Risk' AND Monetary > 5000 THEN 1
        WHEN Segment = 'Champions' THEN 2
        WHEN Segment = 'At Risk' THEN 2
        WHEN Segment = 'Loyal Customers' THEN 3
        WHEN Segment = 'Can''t Lose Them' THEN 2
        ELSE 4
    END AS priority_level,

    -- Suggested campaign based on customer segment and value
    CASE 
        WHEN Segment = 'Champions' AND Monetary > 10000 
            THEN 'VIP Concierge Program'
            
        WHEN Segment = 'Champions' 
            THEN 'VIP Rewards'
            
        WHEN Segment = 'At Risk' AND Monetary > 5000 
            THEN 'Urgent Personal Outreach'
            
        WHEN Segment = 'At Risk' 
            THEN 'Win-Back Email Campaign'
            
        WHEN Segment = 'Loyal Customers' 
            THEN 'Loyalty Program'
            
        WHEN Segment = 'Can''t Lose Them' 
            THEN 'Emergency Recovery'
            
        WHEN Segment = 'New Customers' 
            THEN 'Onboarding Sequence'
            
        WHEN Segment = 'Potential Loyalists' 
            THEN 'Nurture Campaign'
            
        ELSE 'Standard Marketing'
    END AS campaign_type

FROM rfm_analysis

-- Focus only on segments where a targeted campaign makes sense
WHERE Segment IN (
    'Champions',
    'At Risk',
    'Loyal Customers',
    'Can''t Lose Them',
    'New Customers'
)

ORDER BY priority_level ASC, Monetary DESC;


-- Quick check of the highest-priority customers
SELECT *
FROM vw_action_priority
LIMIT 20;


-- ============================================================
-- Final Validation Checks
-- ============================================================

-- Confirm the views were created
SHOW TABLES LIKE 'vw_%';

-- Check the database connection
SELECT @@hostname;

SELECT CURRENT_USER();

SELECT USER();

-- Review all customer segments
USE ecommerce_analytics;

SELECT DISTINCT Segment
FROM rfm_analysis;

-- Final check of the segment summary
SELECT 
    Segment,
    customer_count
FROM vw_segment_summary;