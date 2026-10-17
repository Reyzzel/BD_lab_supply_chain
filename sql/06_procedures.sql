SET search_path TO scm, public;

-- Результат повертається через останній INOUT-параметр

-- Поточний користувач (діє до кінця транзакції або сесії)
CREATE PROCEDURE sp_set_current_user(p_user_id integer, p_session boolean DEFAULT false)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM app_user WHERE id = p_user_id AND is_active) THEN
        RAISE EXCEPTION 'Користувач % не існує або неактивний', p_user_id;
    END IF;
    PERFORM set_config('app.user_id', p_user_id::text, NOT p_session);
END;
$$;

-- Відділ разом із керівником (розв'язує циклічну залежність)
CREATE PROCEDURE sp_department_create(
    p_name            varchar,
    p_phone           varchar,
    p_head_full_name  varchar,
    p_head_position   varchar,
    p_head_salary     numeric,
    INOUT p_department_id integer DEFAULT NULL,
    INOUT p_head_id       integer DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    p_head_id := nextval(pg_get_serial_sequence('scm.employee', 'id'));

    INSERT INTO department (name, phone, head_employee_id)
    VALUES (p_name, p_phone, p_head_id)
    RETURNING id INTO p_department_id;

    INSERT INTO employee (id, full_name, position, salary, department_id)
    VALUES (p_head_id, p_head_full_name, p_head_position, p_head_salary, p_department_id);
END;
$$;

-- Працівники
CREATE PROCEDURE sp_employee_create(
    p_full_name     varchar,
    p_position      varchar,
    p_salary        numeric,
    p_department_id integer,
    p_mentor_id     integer DEFAULT NULL,
    INOUT p_id      integer DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    INSERT INTO employee (full_name, position, salary, department_id, mentor_id)
    VALUES (p_full_name, p_position, p_salary, p_department_id, p_mentor_id)
    RETURNING id INTO p_id;
END;
$$;

CREATE PROCEDURE sp_employee_delete(p_id integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    UPDATE employee SET deleted_at = now() WHERE id = p_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного працівника % не знайдено', p_id;
    END IF;
END;
$$;

-- Клієнти
CREATE PROCEDURE sp_customer_create(
    p_full_name varchar,
    p_phone     varchar,
    p_email     varchar,
    p_address   text,
    INOUT p_id  integer DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    INSERT INTO customer (full_name, phone, email, address)
    VALUES (p_full_name, p_phone, p_email, p_address)
    RETURNING id INTO p_id;
END;
$$;

CREATE PROCEDURE sp_customer_update(
    p_id        integer,
    p_full_name varchar,
    p_phone     varchar,
    p_email     varchar,
    p_address   text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    UPDATE customer
       SET full_name = p_full_name, phone = p_phone, email = p_email, address = p_address
     WHERE id = p_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного клієнта % не знайдено', p_id;
    END IF;
END;
$$;

CREATE PROCEDURE sp_customer_delete(p_id integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM customer_order
                WHERE customer_id = p_id AND status IN ('new', 'confirmed', 'shipped')) THEN
        RAISE EXCEPTION 'У клієнта % є незавершені замовлення', p_id;
    END IF;
    UPDATE customer SET deleted_at = now() WHERE id = p_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного клієнта % не знайдено', p_id;
    END IF;
END;
$$;

CREATE PROCEDURE sp_customer_restore(p_id integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    UPDATE customer SET deleted_at = NULL WHERE id = p_id AND deleted_at IS NOT NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Видаленого клієнта % не знайдено', p_id;
    END IF;
END;
$$;

-- Товари (разом з підтипом)
CREATE PROCEDURE sp_product_create(
    p_sku             varchar,
    p_name            varchar,
    p_price           numeric,
    p_category        product_category,
    p_warranty_months integer DEFAULT NULL,
    p_size            varchar DEFAULT NULL,
    p_material        varchar DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    INSERT INTO product (sku, name, price, category)
    VALUES (p_sku, p_name, p_price, p_category);

    IF p_category = 'electronics' THEN
        IF p_warranty_months IS NULL THEN
            RAISE EXCEPTION 'Для електроніки обов''язковий термін гарантії';
        END IF;
        INSERT INTO electronics (product_sku, warranty_months) VALUES (p_sku, p_warranty_months);
    ELSE
        IF p_size IS NULL OR p_material IS NULL THEN
            RAISE EXCEPTION 'Для одягу обов''язкові розмір і матеріал';
        END IF;
        INSERT INTO clothing (product_sku, size, material) VALUES (p_sku, p_size, p_material);
    END IF;
END;
$$;

CREATE PROCEDURE sp_product_update(
    p_sku             varchar,
    p_name            varchar,
    p_price           numeric,
    p_warranty_months integer DEFAULT NULL,
    p_size            varchar DEFAULT NULL,
    p_material        varchar DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
DECLARE
    v_category product_category;
BEGIN
    UPDATE product SET name = p_name, price = p_price
     WHERE sku = p_sku AND deleted_at IS NULL
    RETURNING category INTO v_category;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного товару % не знайдено', p_sku;
    END IF;

    IF v_category = 'electronics' THEN
        UPDATE electronics SET warranty_months = COALESCE(p_warranty_months, warranty_months)
         WHERE product_sku = p_sku;
    ELSE
        UPDATE clothing SET size     = COALESCE(p_size, size),
                            material = COALESCE(p_material, material)
         WHERE product_sku = p_sku;
    END IF;
END;
$$;

CREATE PROCEDURE sp_product_delete(p_sku varchar)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    UPDATE product SET deleted_at = now() WHERE sku = p_sku AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активного товару % не знайдено', p_sku;
    END IF;
END;
$$;

CREATE PROCEDURE sp_product_restore(p_sku varchar)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    UPDATE product SET deleted_at = NULL WHERE sku = p_sku AND deleted_at IS NOT NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Видаленого товару % не знайдено', p_sku;
    END IF;
END;
$$;

-- Замовлення та рядки
CREATE PROCEDURE sp_order_create(
    p_customer_id integer,
    p_employee_id integer,
    INOUT p_order_number integer DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    INSERT INTO customer_order (customer_id, employee_id)
    VALUES (p_customer_id, p_employee_id)
    RETURNING order_number INTO p_order_number;
END;
$$;

-- Додає товар у замовлення; якщо товар уже є — збільшує кількість
CREATE PROCEDURE sp_order_add_item(
    p_order_number integer,
    p_sku          varchar,
    p_quantity     integer,
    INOUT p_line_number integer DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    -- блокуємо замовлення, щоб номери рядків не дублювалися
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Кількість має бути додатною (передано %)', p_quantity;
    END IF;

    PERFORM 1 FROM customer_order WHERE order_number = p_order_number FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Замовлення % не знайдено', p_order_number;
    END IF;

    UPDATE order_item SET quantity = quantity + p_quantity
     WHERE order_number = p_order_number AND product_sku = p_sku
    RETURNING line_number INTO p_line_number;

    IF NOT FOUND THEN
        INSERT INTO order_item (order_number, product_sku, quantity)
        VALUES (p_order_number, p_sku, p_quantity)
        RETURNING line_number INTO p_line_number;
    END IF;

    IF fn_stock_available(p_sku) < p_quantity THEN
        RAISE NOTICE 'Увага: на складах недостатньо товару % (є %)', p_sku, fn_stock_available(p_sku);
    END IF;
END;
$$;

CREATE PROCEDURE sp_order_remove_item(p_order_number integer, p_line_number integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    DELETE FROM order_item WHERE order_number = p_order_number AND line_number = p_line_number;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Рядок %/% не знайдено', p_order_number, p_line_number;
    END IF;
END;
$$;

-- confirmed / cancelled (shipped і delivered — лише через відвантаження)
CREATE PROCEDURE sp_order_set_status(p_order_number integer, p_status order_status)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    IF p_status = 'cancelled' THEN
        DELETE FROM shipment WHERE order_number = p_order_number AND status = 'pending';
    END IF;

    UPDATE customer_order SET status = p_status WHERE order_number = p_order_number;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Замовлення % не знайдено', p_order_number;
    END IF;
END;
$$;

-- Поставки
CREATE PROCEDURE sp_supply_register(
    p_contract_number varchar,
    p_sku             varchar,
    p_warehouse_id    integer,
    p_delivery_date   date,
    p_quantity        integer,
    INOUT p_id        integer DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    INSERT INTO supply (contract_number, product_sku, warehouse_id, delivery_date, quantity)
    VALUES (p_contract_number, p_sku, p_warehouse_id, p_delivery_date, p_quantity)
    RETURNING id INTO p_id;
END;
$$;

CREATE PROCEDURE sp_supply_set_status(p_id integer, p_status supply_status)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    UPDATE supply SET status = p_status WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Поставку % не знайдено', p_id;
    END IF;
END;
$$;

-- Відвантаження
CREATE PROCEDURE sp_shipment_create(
    p_order_number    integer,
    p_warehouse_id    integer,
    p_tracking_number varchar DEFAULT NULL,
    INOUT p_id        integer DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    INSERT INTO shipment (order_number, warehouse_id, tracking_number)
    VALUES (p_order_number, p_warehouse_id, p_tracking_number)
    RETURNING id INTO p_id;
END;
$$;

CREATE PROCEDURE sp_shipment_set_warehouse(p_id integer, p_warehouse_id integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    UPDATE shipment SET warehouse_id = p_warehouse_id WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Відвантаження % не знайдено', p_id;
    END IF;
END;
$$;

CREATE PROCEDURE sp_shipment_set_status(p_id integer, p_status shipment_status)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = scm, public
AS $$
BEGIN
    UPDATE shipment SET status = p_status WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Відвантаження % не знайдено', p_id;
    END IF;
END;
$$;
