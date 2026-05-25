/**
Tables
1. app_traffic_raw
  - Mobile App Traffic raw data table
  - Contains event-level log data: session, user, product, transaction info
  
2. params
  - Date range parameters for extraction window
 */
CREATE TEMP TABLE params AS
SELECT '2024-10-02'::DATE AS extract_startdate, '2024-10-02'::DATE AS extract_enddate;


CREATE TEMP TABLE in_view_cart AS
SELECT max_event_timestamp_micros , event_name,app_instance_id, item
FROM (
    SELECT max_event_timestamp_micros , event_name,app_instance_id,
        CASE WHEN LOWER(event_name) = 'ecommerce_purchase' THEN unnest(string_to_array(line_items, ','))
             WHEN LOWER(event_name) in ('add_to_cart','carousel_item_click','carousel_item_view','pdp_detail_view','view_item')  THEN unnest(string_to_array(item_id, ','))
             WHEN (LOWER(event_name) = 'add_to_cart_click'  OR LOWER(event_name) = 'buy_now') THEN unnest(string_to_array(line_item_id, ','))
             WHEN (LOWER(event_name) = 'webview_event') THEN unnest(string_to_array(sku, ','))
             WHEN (LOWER(event_name) = 'web_analytics_event') THEN unnest(string_to_array(product_family, ','))
             WHEN (LOWER(webview_event_name) = 'pageview_home') THEN url
            END AS item
    FROM app_traffic_raw, params
    WHERE (LOWER(event_name) IN ('ecommerce_purchase','add_to_cart','carousel_item_click','carousel_item_view','pdp_detail_view','view_item','add_to_cart_click','buy_now')
     OR (LOWER(webview_event_name) = 'pageview_home'))
    AND cast(event_date as Date) BETWEEN params.extract_startdate  and params.extract_enddate )
GROUP BY  max_event_timestamp_micros , event_name,app_instance_id, item
;

CREATE TEMP TABLE cids AS
SELECT max_session_id,
CASE WHEN REGEXP_MATCHES(cid,'(pla-ecomm|imecom_pla).*')
        OR REGEXP_MATCHES(cid,'^(pla-ecom).*')
    THEN 'PLA'
    WHEN REGEXP_MATCHES(cid,'^(dis-cnvr|dis-ecomm|disrtg-ecomm).*')
    THEN 'Display Retargeting'
    WHEN REGEXP_MATCHES(cid,'(smp-ecomm).*')
    THEN 'Social (Paid)'
    WHEN REGEXP_MATCHES(cid,'(sem|SEM).*')
    THEN 'Paid Search'
    WHEN REGEXP_MATCHES(cid,'(ppc|pcc|PPC|PCC).*')
        AND NOT REGEXP_MATCHES(cid,'^(us_pla_google-|pla-|pla_).*')
    THEN 'Paid Search'
    WHEN REGEXP_MATCHES(cid,'^(us_ppc_google|my_ppc_google|sem-ecomm).*')
        AND NOT REGEXP_MATCHES(cid,'^(us_pla_google-|pla-|pla_|sem-mktg-).*')
    THEN 'Paid Search - eComm'
    WHEN REGEXP_MATCHES(cid,'^(opmc-ecom|OPMC-ECOM).*')
    THEN 'Other Paid Ecomm'
    WHEN REGEXP_MATCHES(cid,'^(eml-ecom|eml-new-ecom1-cart|eml-abdn|EML-ABDN).*')
    THEN 'Email - Upsell it'
    WHEN REGEXP_MATCHES(cid,'^(emlcom-).*')
        AND NOT REGEXP_MATCHES(cid,'^(eml-ecom-cart-0516-|eml-new-ecom1-cart-).*')
    THEN 'Email - eComm'
    WHEN REGEXP_MATCHES(cid,'^(em-|eml-|eml|EML|emlcrm-).*')
    THEN 'Email - CRM'
    WHEN REGEXP_MATCHES(cid,'^(em-|eml-|eml|EML).*')
    THEN 'Email (Retired)'
    WHEN REGEXP_MATCHES(cid,'^(dis).*')
    THEN 'Display'
    WHEN REGEXP_MATCHES(cid,'(pla_|pla-).*')
    THEN 'PLA'
    WHEN REGEXP_MATCHES(cid,'(afl|AFL).*')
    THEN 'Affiliate'
--      WHEN REGEXP_MATCHES(cid,'(epp).*')
--      OR store_id is not NULL
--      THEN 'EPP'
    WHEN REGEXP_MATCHES(cid,'^(pnf).*')
        OR REGEXP_MATCHES(cid,'(psh).*')
    THEN 'Push Notifications'
    WHEN REGEXP_MATCHES(cid,'(smc|smp|ecomfb).*')
    THEN 'Social (Paid)'
    WHEN cid is not NULL
    THEN 'Other External Campaign'
    WHEN REGEXP_MATCHES(utm_medium,'^organic.*')
    THEN 'Natural Search'
    WHEN (REGEXP_MATCHES(utm_source,'(direct)') AND REGEXP_MATCHES(utm_medium,'(none)'))
        OR (REGEXP_MATCHES(utm_source,'app') AND REGEXP_MATCHES(utm_medium,'intent_filter'))
    THEN 'Direct'
    WHEN REGEXP_MATCHES(cid,'^(smf-).*')
    THEN 'Social (Free and Owned)'
    WHEN REGEXP_MATCHES(cid,'^(van-).*')
    THEN 'Vanity'
    WHEN REGEXP_MATCHES(cid,'(smc|smp|ecomfb).*')
    THEN 'Referring Domains'
    ELSE 'Direct'
    END as channel_group3
    from (
        SELECT max_session_id, cid, utm_medium, utm_source,ROW_NUMBER() OVER (PARTITION BY max_session_id ORDER BY max_event_time_est) AS row_num
        FROM app_traffic_raw, params
        WHERE cid IS NOT NULL and cast(event_date as Date) BETWEEN params.extract_startdate and params.extract_enddate
        ) df
where row_num = 1
;

CREATE TEMP TABLE total_for_daily_ AS
SELECT 'COUNTRY_A' as country_cd, t0.max_event_timestamp_micros,t0.min_event_timestamp_micros, t0.platform, LOWER(t0.event_name) AS event_name, LOWER(t0.webview_event_name) AS webview_event_name,
        t0.event_date, t0.app_instance_id, r_table.transaction_id,
        t0.max_session_id AS unique_session_id, t0.app_open_user_engagement, t0.max_session_start_time, t0.max_session_end_time,
        CASE WHEN (
            (LOWER(t0.event_name) = 'login')
            OR (t0.acct_type IN ('brand_account','brand_account'))
            OR (max_event_params LIKE '%account%type%brand%account%')
            OR (max_event_params LIKE '%acct%type%brand%account%')
            OR (max_event_params LIKE '%loggedin_status, {null, null, true}%')
            OR (max_event_params LIKE '%forcelogin=true%')
            ) THEN 'LOGIN'
        END AS login_status,
        CASE WHEN channel_group3 is null then 'Direct'
        else channel_group3
        END as channel_group3,
    CASE
        WHEN (REGEXP_MATCHES(item,'^(mobile|smartphone|tablet|watch|wearable|accessory|laptop).*' )
            AND NOT REGEXP_MATCHES(item,'iot'))
            OR (REGEXP_MATCHES(item,'^(mob-|phn-|tab-|wat-|ear-|acc-|spk-|cbl-|chg-|cvr-|cas-|scr-|prt-|kbd-|mou-|hub-).*'))
            THEN 'IM'
        WHEN (REGEXP_MATCHES(item ,'^(tv|television|monitor|home_audio|display|audio|projector|soundbar|lifestyle_display).*' ))
            OR ((REGEXP_MATCHES(item ,'^(tv-|mon-|dis-|prj-|aud-|snd-|bar-|sig-|frm-|lft-|srs-|lst-|qled-|neo-|frm-|pnl-|led-|oled-|qd-).*')
                OR (REGEXP_MATCHES(item ,'^micro led'))
                OR (REGEXP_MATCHES(item ,'^be.*-h$'))
                OR (REGEXP_MATCHES(item ,'^un.*')
                    AND NOT REGEXP_MATCHES(item ,'^unspecified.*'))
                OR (REGEXP_MATCHES(item ,'^gu.*')
                    AND NOT REGEXP_MATCHES(item ,'^guijiaoyouhuiquan.*'))
                OR (REGEXP_MATCHES(item ,'^lh.*')
                    AND NOT REGEXP_MATCHES(item ,'^lh0.*'))
                    )
                AND (NOT REGEXP_MATCHES(item ,'^f30|.*covergsm.*')))
            THEN 'VD'
        WHEN (REGEXP_MATCHES(item ,'^(dishwasher|oven|refrigerator|vacuum|washing_machine|home_appliance|air_conditioner|microwave|washer|dryer).*') )
            OR ((REGEXP_MATCHES(item ,'^(ref-|fre-|was-|dry-|dis-|ove-|mic-|vac-|air-|acp-|hum-|cln-|flt-|bot-|crp-|rng-|coo-).*')
                OR (REGEXP_MATCHES(item ,'^ar.*')
                    AND NOT REGEXP_MATCHES(item ,'^artstore.*'))
                OR (REGEXP_MATCHES(item ,'^nl.*')
                    AND NOT REGEXP_MATCHES(item ,'^nl-1yr.*'))
                OR (REGEXP_MATCHES(item ,'^ms.*')
                    AND NOT REGEXP_MATCHES(item ,'^(ms-kb|ms-mo).*'))
                OR (REGEXP_MATCHES(item ,'^(cfx|frh|frc|fpc|ra-kscrq|s-1|ra-k|ra-b2|ra-f|ra-m|ra-r|ra-c|haf|f-hub|hd|vca|ma-cf|skk-|sk-|f-str|f-mlt|we357|fsc1412z3|p-|we402|we272|we302|ma-tk|ra-timo|rat42|raf36).*')
                    AND NOT REGEXP_MATCHES(item ,'^(p-qt|p-gt|p-qs|p-uh|p-ut|p-prj).*'))))
            THEN 'HA'
        ELSE 'Others'
        END AS product_division,
    Case when currentmode = 'b2b' Then 'SMB'
        when store_id is NOT null or REGEXP_MATCHES(t0.cid,'(epp).*') or utm_campaign like '%epp%' or REGEXP_MATCHES(max_event_params,'(store_name).') Then 'EPP'
        when currentmode = 'b2c' Then 'B2C'
        else 'unknown' end as biz_type,
    r_table.revenue as revenue
FROM (
    SELECT *
    FROM app_traffic_raw, params
    Where cast(event_date as Date) BETWEEN params.extract_startdate  and params.extract_enddate
      AND event_name not in ('notification_receive','fcm_notification_receive','notification_dismiss')
) t0
--JOIN (SELECT max_session_id FROM read_parquet('./data/*20250710.parquet'), params
--      WHERE event_name in ('session_start', 'app_open') and cast(event_date as Date) BETWEEN params.extract_startdate  and params.extract_enddate) id
--      on id.max_session_id = t0.max_session_id
LEFT JOIN cids on t0.max_session_id = cids.max_session_id
LEFT JOIN in_view_cart ON t0.max_event_timestamp_micros = in_view_cart.max_event_timestamp_micros
    AND LOWER(t0.event_name) = LOWER(in_view_cart.event_name)
    AND t0.app_instance_id = in_view_cart.app_instance_id
LEFT JOIN (
    select transaction_id, max(user_id) as user_id, max(CAST(REPLACE(value, ',', '') AS DECIMAL(15, 0))) as revenue
    from app_traffic_raw, params
    WHERE event_name = 'ecommerce_purchase'
    --     and transaction_id is not null
    and cast(event_date as Date) BETWEEN params.extract_startdate  and params.extract_enddate
    group by transaction_id
) r_table
on t0.transaction_id = r_table.transaction_id
  and t0.user_id =r_table.user_id
;

CREATE TEMP TABLE total_for_daily AS
SELECT *
FROM (
    SELECT country_cd, max_event_timestamp_micros,min_event_timestamp_micros, platform, event_name, webview_event_name, event_date, app_instance_id, unique_session_id, app_open_user_engagement, channel_group3, product_division, revenue, transaction_id, max_session_start_time, max_session_end_time,
        CASE WHEN app_instance_id IN ( SELECT app_instance_id FROM total_for_daily_ WHERE login_status ='LOGIN')
            THEN 'LOGIN' ELSE 'LOGOUT' END AS login_status,
        CASE WHEN (unique_session_id IN (SELECT unique_session_id FROM total_for_daily_ WHERE biz_type = 'SMB')) THEN 'SMB'
            WHEN (unique_session_id IN (SELECT unique_session_id FROM total_for_daily_ WHERE biz_type = 'EPP')) THEN 'EPP'
            ELSE biz_type
            END AS biz_type
    FROM total_for_daily_
) a
GROUP BY country_cd, max_event_timestamp_micros,min_event_timestamp_micros, platform, event_name, webview_event_name, event_date, app_instance_id, unique_session_id, app_open_user_engagement, login_status, channel_group3, product_division, biz_type, revenue, transaction_id, max_session_start_time, max_session_end_time
;

CREATE TEMP TABLE atc AS
SELECT event_date, unique_session_id, biz_type, product_division, channel_group3, MIN(max_event_timestamp_micros) AS atc_time,
FROM total_for_daily
WHERE LOWER(event_name) IN ('add_to_cart', 'add_to_cart_click')
GROUP BY event_date, biz_type, product_division, channel_group3, unique_session_id
;

CREATE TEMP TABLE purchase_event AS
SELECT
    event_date, platform,
    Case
        WHEN currentmode = 'b2b' Then 'SMB'
        WHEN store_id is not NULL Then 'EPP'
        else 'B2C' end as biz_type,
     app_instance_id , count(DISTINCT ts) as event_count
FROM (select event_date, max_event_time_pst as ts,store_id,  platform, unnest(str_split(line_items,',')) as item, app_instance_id,event_name,currentmode
    from app_traffic_raw, params
    WHERE 1=1
      AND cast(event_date as Date) BETWEEN (params.extract_startdate - INTERVAL 2 YEAR )
      AND (params.extract_enddate - INTERVAL 1 DAY )
      AND event_name IN ('purchase','ecommerce_purchase')) t00
    GROUP BY event_date, platform,biz_type,
        app_instance_id
;

CREATE TEMP TABLE final_daily_mart_ AS
SELECT
      t1.event_date,
      t1.event_date_form,
      t1.max_event_timestamp_micros,
      t1.country_cd,
      t1.biz_type,
      t1.platform,
      t1.channel_group3,
      CASE WHEN event_name IN ('viewing_cart','viewing_checkout') THEN COALESCE(t2.product_division, 'Others') ELSE COALESCE(t1.product_division, 'Others') END AS product_division,
      t1.event_name,
      t1.webview_event_name,
      t1.app_instance_id,
      t1.unique_session_id,
      t1.app_open_user_engagement,
      t1.transaction_id,
      t1.login_status,
      t1.revenue,
      t1.purchase_count,
      t3.event_date AS event_date_t3,
      t2.atc_time AS atc_time_t2,
      EXTRACT(EPOCH FROM (to_timestamp(CAST(t1.max_event_timestamp_micros AS BIGINT) / 10000000) - to_timestamp(CAST(t1.min_event_timestamp_micros AS BIGINT) / 10000000))) AS timespenttotal
  FROM (
    SELECT
      country_cd,
      max_event_timestamp_micros,
      platform,
      event_name,
      webview_event_name,
      event_date,
      STRPTIME(event_date, '%Y-%m-%d') AS event_date_form,
      app_instance_id,
      unique_session_id,
      app_open_user_engagement,
      transaction_id,
      max_session_end_time,
      max_session_start_time,
      min_event_timestamp_micros,
      CASE WHEN unique_session_id IN ( SELECT unique_session_id FROM total_for_daily WHERE login_status ='LOGIN')
        THEN 'LOGIN' ELSE 'LOGOUT'
      END AS login_status,
      channel_group3,
      product_division,
      CASE
        WHEN (unique_session_id IN (SELECT unique_session_id FROM total_for_daily WHERE biz_type = 'SMB')) THEN 'SMB'
        WHEN  (unique_session_id IN (SELECT unique_session_id FROM total_for_daily WHERE biz_type = 'EPP')) THEN 'EPP'
        ELSE 'B2C'
      END AS biz_type,
      revenue,
      (
      SUM( CASE WHEN LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' ) THEN 1 END )
      OVER ( PARTITION BY event_date, app_instance_id, biz_type, platform, product_division, event_name, max_event_timestamp_micros ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING )
      ) AS purchase_count
    FROM total_for_daily
  ) AS t1
  LEFT JOIN atc AS t2 ON t1.biz_type = t2.biz_type
    AND t1.event_date = t2.event_date
    AND t1.unique_session_id = t2.unique_session_id
  LEFT JOIN purchase_event AS t3
  ON t1.app_instance_id = t3.app_instance_id
    AND t1.biz_type = t3.biz_type
    AND t1.platform = t3.platform
;

CREATE TEMP TABLE final_daily_mart AS
SELECT
    *,
    STRFTIME(STRPTIME(event_date, '%Y-%m-%d'), '%Y-%m') AS event_date_mau,
    CONCAT(STRFTIME(STRPTIME(event_date, '%Y-%m-%d'), '%Y'),
           '-W',
           EXTRACT(WEEK FROM cast(event_date as Date))) AS event_date_wau,
    CAST(SUM(CASE
        WHEN REGEXP_MATCHES(LOWER(event_name), 'first_open|app_open_first_time')
        THEN 1
    END) OVER (PARTITION BY event_date, unique_session_id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS INTEGER) AS first_open_visit,
  FROM final_daily_mart_
;


---  MKTCH Total
SELECT
    dau.event_date_local,
    dau.country_cd,
    dau.biz_type,
    dau.platform,
    dau.product_division,
    '' AS channel_group1,
    '' AS channel_group2,
    'Total' AS channel_group3,
    CASE WHEN dau.is_grouped = 1 THEN dau.app_install ELSE 0 END AS app_install,
    dau.shopper_visit,
    dau.shopper_visit AS dot_com_visit,
    dau.shopper_visit AS entry,
    dau.bounce,
    dau.pdp_visit,
    dau.add_to_cart_visit,
    dau.cart_page_visit,
    dau.checkout_page_visit,
    dau.order_visit,
    dau.orders,
    dau.revenue,
    dau.adobe_app_total_unique_visitor,
    CASE WHEN dau.is_grouped = 1 THEN dau.adobe_app_active_user ELSE 0 END AS adobe_app_active_user,
    CASE WHEN dau.is_grouped = 1 THEN mau.adobe_app_monthly_active_user ELSE 0 END AS adobe_app_monthly_active_user,
    CASE WHEN dau.is_grouped = 1 THEN wau.adobe_app_weekly_active_user ELSE 0 END AS adobe_app_weekly_active_user,
    CASE WHEN dau.is_grouped = 1 THEN dau.adobe_app_new_active_user ELSE 0 END AS adobe_app_new_active_user,
    dau.adobe_app_login_unique_visitor,
    dau.adobe_app_ordered_unique_visitor,
    dau.adobe_app_login_ordered_visitor,
    CASE WHEN dau.is_grouped = 1 THEN dau.adobe_app_new_ordered_visitor ELSE 0 END AS adobe_app_new_ordered_visitor,
    CASE WHEN dau.is_grouped = 1 THEN dau.adobe_app_exist_ordered_visitor ELSE 0 END AS adobe_app_exist_ordered_visitor,
    time_table.time_spent
FROM (
    SELECT
    event_date AS event_date_local, event_date_mau, event_date_wau, country_cd, platform,
    biz_type,
    CASE
        WHEN product_division IS NULL THEN 'ALL'
        ELSE product_division
    END AS product_division,
    GROUPING(product_division) AS is_grouped,
    COUNT(DISTINCT IF (LOWER(event_name) IN ( 'first_open', 'app_open_first_time', 'install_referrer_new', 'install_referrer' ), app_instance_id, NULL ) ) AS app_install,
    COUNT(DISTINCT IF (LOWER(event_name) IN ( 'app_remove' ), app_instance_id, NULL ) ) AS app_uninstall,
    COUNT(DISTINCT IF(app_open_user_engagement= '1', unique_session_id, NULL ) ) AS shopper_visit,
    COUNT(DISTINCT IF(app_open_user_engagement= '0', unique_session_id, NULL ) ) AS bounce,
    COUNT(DISTINCT IF(LOWER(event_name) IN ('view_item', 'pdp_detail_view') OR LOWER(webview_event_name) = 'pageview_home' , unique_session_id, NULL ) ) AS pdp_visit,
    COUNT(DISTINCT IF(LOWER(event_name) IN ('add_to_cart', 'add_to_cart_click'), unique_session_id, NULL ) ) AS add_to_cart_visit,
    COUNT(DISTINCT IF((LOWER(event_name) = 'viewing_cart' AND max_event_timestamp_micros >= atc_time_t2 ), unique_session_id, NULL ) ) AS cart_page_visit,
    COUNT(DISTINCT IF(LOWER(event_name) IN ( 'viewing_checkout','checkout_progress', 'cart_shipping_info', 'pay_now', 'begin_checkout', 'add_shipping_info', 'checkout_started_order_details' ),
        unique_session_id, NULL ) ) AS checkout_page_visit,
    COUNT(DISTINCT IF(LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' ), unique_session_id, NULL ) ) AS order_visit,
    COUNT(DISTINCT IF(LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' ), transaction_id, NULL ) ) AS orders,
    COALESCE(SUM(revenue) , 0) AS revenue,
    COUNT(DISTINCT IF (app_open_user_engagement= '1', app_instance_id, NULL)) AS adobe_app_total_unique_visitor,
    COUNT(DISTINCT IF ( LOWER(event_name) IN ('user_engagement'), app_instance_id, NULL ) ) AS adobe_app_active_user,
    COUNT(DISTINCT IF( (first_open_visit >= 1) AND ( LOWER(event_name) IN ('user_engagement') ), app_instance_id, NULL )) AS adobe_app_new_active_user,
    COUNT(DISTINCT IF(login_status = 'LOGIN' and app_open_user_engagement = '1', app_instance_id, NULL )) AS adobe_app_login_unique_visitor,
    COUNT(DISTINCT CASE WHEN (LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' ) ) THEN app_instance_id END ) AS adobe_app_ordered_unique_visitor,
    COUNT(DISTINCT CASE WHEN (LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' ) AND login_status = 'LOGIN' ) THEN app_instance_id END ) AS adobe_app_login_ordered_visitor,
    COUNT(DISTINCT IF(LOWER(event_name) IN ('purchase', 'ecommerce_purchase' ) AND purchase_count = 1
                       AND (event_date_t3 IS NULL OR CAST(event_date_t3 AS DATE) NOT BETWEEN (event_date_form - INTERVAL '2 YEAR') AND (event_date_form - INTERVAL '1 DAY')), app_instance_id, NULL )) AS adobe_app_new_ordered_visitor,
    COUNT(DISTINCT IF(((LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' )
        AND (event_date_t3 IS NOT NULL AND CAST(event_date_t3 AS DATE) BETWEEN (event_date_form - INTERVAL '2 YEAR') AND (event_date_form - INTERVAL '1 DAY')))
        OR (LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' ) AND purchase_count >= 2)), app_instance_id, NULL )) AS adobe_app_exist_ordered_visitor
    FROM final_daily_mart
    GROUP BY GROUPING SETS (
        (event_date, event_date_mau, event_date_wau, country_cd, platform, biz_type, product_division),
        (event_date, event_date_mau, event_date_wau, country_cd, platform, biz_type)
    )
) AS dau
LEFT JOIN (
    SELECT country_cd, platform, biz_type, event_date_mau,
           COUNT(DISTINCT IF (LOWER(event_name) IN ('user_engagement'), app_instance_id, NULL)) AS adobe_app_monthly_active_user
    FROM final_daily_mart
    GROUP BY country_cd, platform, biz_type, event_date_mau
) AS mau
ON dau.event_date_mau = mau.event_date_mau
   AND dau.platform = mau.platform
   AND dau.biz_type = mau.biz_type
   AND dau.country_cd = mau.country_cd
LEFT JOIN (
    SELECT country_cd, platform, biz_type, event_date_wau,
           COUNT(DISTINCT IF (LOWER(event_name) IN ('user_engagement'), app_instance_id, NULL)) AS adobe_app_weekly_active_user
    FROM final_daily_mart
    GROUP BY country_cd, platform, biz_type, event_date_wau
) AS wau
ON dau.event_date_wau = wau.event_date_wau
   AND dau.platform = wau.platform
   AND dau.biz_type = wau.biz_type
   AND dau.country_cd = wau.country_cd
LEFT JOIN (
    SELECT
        time1.country_cd,
        time1.event_date,
        time1.biz_type,
        time1.platform,
        CASE
            WHEN base.product_division IS NULL THEN 'ALL'
            ELSE base.product_division
        END AS product_division,
        CAST(AVG(time1.timespenttotal) AS BIGINT) AS time_spent
    FROM (
        SELECT country_cd, event_date, biz_type, platform, final_daily_mart.unique_session_id, MAX(timespenttotal) AS timespenttotal
        FROM final_daily_mart
        JOIN (
            SELECT unique_session_id
            FROM total_for_daily
            WHERE event_name in ('session_start', 'app_open')
              AND max_event_timestamp_micros = min_event_timestamp_micros
        ) timefilters ON final_daily_mart.unique_session_id = timefilters.unique_session_id
        GROUP BY country_cd, event_date, biz_type, platform, final_daily_mart.unique_session_id
    ) AS time1
    LEFT JOIN (
        SELECT country_cd, event_date, biz_type, platform, unique_session_id, product_division
        FROM final_daily_mart
    ) AS base
    ON time1.country_cd = base.country_cd
        AND time1.event_date = base.event_date
        AND time1.biz_type = base.biz_type
        AND time1.platform = base.platform
        AND time1.unique_session_id = base.unique_session_id
    GROUP BY GROUPING SETS (
        (time1.country_cd, time1.event_date, time1.biz_type, time1.platform, base.product_division),
        (time1.country_cd, time1.event_date, time1.biz_type, time1.platform)
    )
) AS time_table
ON dau.event_date_local = time_table.event_date
   AND dau.country_cd = time_table.country_cd
   AND dau.biz_type = time_table.biz_type
   AND dau.platform = time_table.platform
   AND dau.product_division  = time_table.product_division
UNION ALL
--- Div. ALL+3Div with MKT MKTCH (Part3,4)
SELECT dau.event_date_local,
       dau.country_cd,
       dau.biz_type,
       dau.platform,
       CASE WHEN dau.product_division IS NULL THEN 'ALL'
            ELSE dau.product_division
           END AS product_division,
       '' AS channel_group1,
       '' AS channel_group2,
       dau.channel_group3,
       0 as app_install,
       dau.shopper_visit,
       dau.shopper_visit as dot_com_visit,
       dau.shopper_visit as entry,
       dau.bounce,
       dau.pdp_visit,
       dau.add_to_cart_visit,
       dau.cart_page_visit,-- dau.cart_page_visit_withoutatc,
       dau.checkout_page_visit,
       dau.order_visit,
       dau.orders,
       dau.revenue,
       0 as adobe_app_total_unique_visitor,
       0 as adobe_app_active_user,
       0 as adobe_app_monthly_active_user,
       0 as adobe_app_weekly_active_user,
       0 as adobe_app_new_active_user,
       0 as adobe_app_login_unique_visitor,
       0 as adobe_app_ordered_unique_visitor,
       0 as adobe_app_login_ordered_visitor,
       0 as adobe_app_new_ordered_visitor,
       0 as adobe_app_exist_ordered_visitor,
       0 as time_spent
FROM (
     SELECT
         event_date as event_date_local,
         event_date_mau,
         event_date_wau,
         country_cd,
         platform,
         product_division,
         biz_type AS biz_type,
         channel_group3,
         COUNT(DISTINCT IF(app_open_user_engagement= '1', unique_session_id, NULL ) ) as shopper_visit,
         COUNT(DISTINCT IF(app_open_user_engagement= '0', unique_session_id, NULL ) ) as bounce,
         COUNT(DISTINCT IF(LOWER(event_name) IN ('view_item', 'pdp_detail_view') OR LOWER(webview_event_name) = 'pageview_home' , unique_session_id, NULL ) ) AS pdp_visit,
         COUNT(DISTINCT IF(LOWER(event_name) IN ('add_to_cart', 'add_to_cart_click'), unique_session_id, NULL ) ) AS add_to_cart_visit,
         COUNT(DISTINCT IF((LOWER(event_name) = 'viewing_cart' AND max_event_timestamp_micros >= atc_time_t2 ), unique_session_id, NULL ) ) AS cart_page_visit,
         COUNT(DISTINCT IF(LOWER(event_name) IN ( 'viewing_checkout','checkout_progress', 'cart_shipping_info', 'pay_now', 'begin_checkout', 'add_shipping_info', 'checkout_started_order_details' ),
                           unique_session_id, NULL ) ) AS checkout_page_visit,
         COUNT(DISTINCT IF(LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' ), unique_session_id, NULL ) ) AS order_visit,
         COUNT(DISTINCT IF(LOWER(event_name) IN ( 'purchase', 'ecommerce_purchase' ), transaction_id, NULL ) ) AS orders,
         COALESCE(SUM(revenue), 0) AS revenue
    FROM final_daily_mart
    GROUP BY GROUPING SETS (
        (event_date, event_date_mau, event_date_wau, country_cd, platform, biz_type, channel_group3, product_division),
        (event_date, event_date_mau, event_date_wau, country_cd, platform, biz_type, channel_group3)
    )
) dau
ORDER BY dau.event_date_local, dau.biz_type, dau.platform, dau.product_division, dau.channel_group3;