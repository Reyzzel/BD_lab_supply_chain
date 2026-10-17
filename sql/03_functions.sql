SET search_path TO scm, public;


-- Встановлюється через sp_set_current_user на початку транзакції
CREATE FUNCTION fn_current_user_id()
RETURNS integer
LANGUAGE sql STABLE
AS $$
    SELECT NULLIF(current_setting('app.user_id', true), '')::integer
$$;


-- SECURITY DEFINER: роль застосунку не має доступу до таблиць

CREATE FUNCTION fn_order_total(p_order_number integer)
RETURNS numeric(12,2)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = scm, public
AS $$
    SELECT COALESCE(sum(quantity * unit_price), 0)::numeric(12,2)
      FROM order_item
     WHERE order_number = p_order_number
$$;

-- p_warehouse_id = NULL: по всіх активних складах
CREATE FUNCTION fn_stock_available(p_sku varchar, p_warehouse_id integer DEFAULT NULL)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = scm, public
AS $$
    SELECT COALESCE(sum(ws.quantity), 0)::integer
      FROM warehouse_stock ws
      JOIN warehouse w ON w.id = ws.warehouse_id
     WHERE ws.product_sku = p_sku
       AND w.deleted_at IS NULL
       AND (p_warehouse_id IS NULL OR ws.warehouse_id = p_warehouse_id)
$$;

CREATE FUNCTION fn_is_contract_valid(p_contract_number varchar, p_on date DEFAULT current_date)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = scm, public
AS $$
    SELECT EXISTS (SELECT 1 FROM contract
                    WHERE contract_number = p_contract_number
                      AND deleted_at IS NULL
                      AND p_on BETWEEN sign_date AND expiry_date)
$$;

-- NULL = без ліміту
CREATE FUNCTION fn_contract_remaining(p_contract_number varchar, p_sku varchar)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = scm, public
AS $$
    SELECT ci.max_quantity - COALESCE((SELECT sum(s.quantity)
                                         FROM supply s
                                        WHERE s.contract_number = ci.contract_number
                                          AND s.product_sku     = ci.product_sku
                                          AND s.status <> 'rejected'), 0)::integer
      FROM contract_item ci
     WHERE ci.contract_number = p_contract_number
       AND ci.product_sku     = p_sku
$$;

-- Лише доставлені поставки, за контрактною ціною
CREATE FUNCTION fn_supplier_turnover(p_edrpou varchar, p_from date, p_to date)
RETURNS numeric(14,2)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = scm, public
AS $$
    SELECT COALESCE(sum(s.quantity * ci.agreed_price), 0)::numeric(14,2)
      FROM supply s
      JOIN contract c       ON c.contract_number = s.contract_number
      JOIN contract_item ci ON ci.contract_number = s.contract_number
                           AND ci.product_sku     = s.product_sku
     WHERE c.supplier_edrpou = p_edrpou
       AND s.status = 'delivered'
       AND s.delivery_date BETWEEN p_from AND p_to
$$;

-- Стажери на всіх рівнях
CREATE FUNCTION fn_employee_mentees(p_mentor_id integer)
RETURNS TABLE (employee_id integer, full_name varchar, job_position varchar, level integer)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = scm, public
AS $$
    WITH RECURSIVE tree AS (
        SELECT e.id, e.full_name, e.position, 1 AS level
          FROM employee e
         WHERE e.mentor_id = p_mentor_id AND e.deleted_at IS NULL
        UNION ALL
        SELECT e.id, e.full_name, e.position, t.level + 1
          FROM employee e
          JOIN tree t ON e.mentor_id = t.id
         WHERE e.deleted_at IS NULL AND t.level < 50
    )
    SELECT id, full_name, position, level FROM tree ORDER BY level, full_name
$$;

CREATE FUNCTION fn_record_history(p_table_name varchar, p_record_id varchar)
RETURNS TABLE (changed_at timestamptz, operation varchar, username varchar,
               old_data jsonb, new_data jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = scm, public
AS $$
    SELECT a.changed_at, a.operation, u.username, a.old_data, a.new_data
      FROM audit_log a
      LEFT JOIN app_user u ON u.id = a.changed_by
     WHERE a.table_name = p_table_name
       AND a.record_id  = p_record_id
     ORDER BY a.id
$$;
