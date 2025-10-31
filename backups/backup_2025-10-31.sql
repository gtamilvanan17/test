

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."user_role" AS ENUM (
    'admin',
    'standard',
    'guest'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_user_account"("p_email" "text", "p_password" "text", "p_name" "text", "p_role" "public"."user_role" DEFAULT 'standard'::"public"."user_role", "p_phone" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  -- Check if user already exists in auth.users
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = p_email
  LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    -- User already exists, just return their ID
    RETURN v_user_id;
  END IF;

  -- Insert into auth.users
  INSERT INTO auth.users (
    id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token
  )
  VALUES (
    gen_random_uuid(),
    p_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    jsonb_build_object('name', p_name, 'username', p_email),
    now(),
    now(),
    encode(gen_random_bytes(32), 'hex'),
    encode(gen_random_bytes(32), 'hex')
  )
  RETURNING id INTO v_user_id;

  -- Insert into profiles (if not exists)
  INSERT INTO public.profiles (user_id, username, role)
  VALUES (v_user_id, p_email, p_role)
  ON CONFLICT (user_id) DO NOTHING;

  -- Insert into user_profiles (if not exists)
  INSERT INTO public.user_profiles (user_id, name, phone, status)
  VALUES (v_user_id, p_name, p_phone, 'active')
  ON CONFLICT (user_id) DO NOTHING;

  RETURN v_user_id;
END;
$$;


ALTER FUNCTION "public"."create_user_account"("p_email" "text", "p_password" "text", "p_name" "text", "p_role" "public"."user_role", "p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_invoice_number"() RETURNS "text"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN 'INV-' || TO_CHAR(NOW(), 'YYYYMM') || '-' || LPAD(nextval('billing_invoice_seq')::TEXT, 4, '0');
END;
$$;


ALTER FUNCTION "public"."generate_invoice_number"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_unique_id_orders"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.unique_id := 'ORD-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(NEW.serial_number::TEXT, 4, '0');
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_unique_id_orders"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_unique_id_outsourcing"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.unique_id := 'OUT-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(NEW.serial_number::TEXT, 4, '0');
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_unique_id_outsourcing"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_unique_id_products"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.unique_id := 'PRD-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(NEW.serial_number::TEXT, 4, '0');
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."generate_unique_id_products"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_role"("user_id" "uuid") RETURNS "public"."user_role"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
BEGIN
  RETURN (SELECT role FROM public.profiles WHERE profiles.user_id = $1);
END;
$_$;


ALTER FUNCTION "public"."get_user_role"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Insert into profiles table
  INSERT INTO public.profiles (user_id, username, role)
  VALUES (NEW.id, NEW.raw_user_meta_data ->> 'username', 'admin'::user_role);
  
  -- Insert into user_profiles table with default values
  INSERT INTO public.user_profiles (user_id, name, status, login_ip)
  VALUES (NEW.id, NEW.raw_user_meta_data ->> 'name', 'active', NEW.raw_user_meta_data ->> 'login_ip');
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_inventory_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.last_updated = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_inventory_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_last_login"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE user_profiles 
  SET last_login = now() 
  WHERE user_id = NEW.user_id;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_last_login"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."activity_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "details" "jsonb",
    "ip_address" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."activity_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "quantity" integer DEFAULT 0 NOT NULL,
    "min_quantity" integer DEFAULT 0 NOT NULL,
    "location" "text" DEFAULT 'Main Warehouse'::"text",
    "last_updated" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."inventory" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_name" "text" NOT NULL,
    "category_id" "uuid",
    "customer_name" "text" NOT NULL,
    "customer_email" "text",
    "customer_phone" "text" DEFAULT ''::"text" NOT NULL,
    "customer_address" "text",
    "outsourcing_id" "uuid",
    "price_quoted" numeric(10,2),
    "quantity" integer DEFAULT 1 NOT NULL,
    "status" "text" DEFAULT 'pending'::"text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "product_id" "uuid",
    "investment_price" numeric DEFAULT 0,
    "actual_price" numeric DEFAULT 0,
    "order_date" "date" DEFAULT CURRENT_DATE,
    "payment_status" "text" DEFAULT 'Pending'::"text",
    "product_name" "text",
    "shipping_fee" numeric DEFAULT 0,
    "serial_number" integer NOT NULL,
    "unique_id" "text",
    "notes" "text",
    "created_by_email" "text",
    CONSTRAINT "orders_payment_status_check" CHECK (("payment_status" = ANY (ARRAY['Pending'::"text", 'Paid'::"text", 'Un paid'::"text", 'Advance Paid'::"text", 'Refunded'::"text", 'Own Use'::"text"])))
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."orders_serial_number_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."orders_serial_number_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."orders_serial_number_seq" OWNED BY "public"."orders"."serial_number";



CREATE TABLE IF NOT EXISTS "public"."outsourcing_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "location" "text",
    "products" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pricing_per_unit" numeric DEFAULT 0,
    "contact_email" "text",
    "contact_phone" "text",
    "address" "text",
    "phone" "text",
    "notes" "text",
    "serial_number" integer NOT NULL,
    "unique_id" "text"
);


ALTER TABLE "public"."outsourcing_profiles" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."outsourcing_profiles_serial_number_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."outsourcing_profiles_serial_number_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."outsourcing_profiles_serial_number_seq" OWNED BY "public"."outsourcing_profiles"."serial_number";



CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "sku" "text" NOT NULL,
    "price" numeric(10,2) DEFAULT 0 NOT NULL,
    "category_id" "uuid",
    "supplier_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "cus_price" numeric DEFAULT 0,
    "inv_price" numeric DEFAULT 0,
    "notes" "text",
    "outsourcing_id" "uuid",
    "serial_number" integer NOT NULL,
    "unique_id" "text"
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."products_serial_number_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."products_serial_number_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."products_serial_number_seq" OWNED BY "public"."products"."serial_number";



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "username" "text",
    "role" "public"."user_role" DEFAULT 'guest'::"public"."user_role",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."stock_movements" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "movement_type" "text" NOT NULL,
    "quantity" integer NOT NULL,
    "reason" "text",
    "reference_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "stock_movements_movement_type_check" CHECK (("movement_type" = ANY (ARRAY['in'::"text", 'out'::"text", 'adjustment'::"text"])))
);


ALTER TABLE "public"."stock_movements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "address" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "profile_picture" "text",
    "description" "text",
    "date_of_birth" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text",
    "phone" "text",
    "status" "text" DEFAULT 'active'::"text",
    "last_login" timestamp with time zone,
    "login_ip" "text"
);


ALTER TABLE "public"."user_profiles" OWNER TO "postgres";


ALTER TABLE ONLY "public"."orders" ALTER COLUMN "serial_number" SET DEFAULT "nextval"('"public"."orders_serial_number_seq"'::"regclass");



ALTER TABLE ONLY "public"."orders" ALTER COLUMN "unique_id" SET DEFAULT ((('ORD-'::"text" || "to_char"("now"(), 'YYYYMMDD'::"text")) || '-'::"text") || "lpad"(("nextval"('"public"."orders_serial_number_seq"'::"regclass"))::"text", 4, '0'::"text"));



ALTER TABLE ONLY "public"."outsourcing_profiles" ALTER COLUMN "serial_number" SET DEFAULT "nextval"('"public"."outsourcing_profiles_serial_number_seq"'::"regclass");



ALTER TABLE ONLY "public"."outsourcing_profiles" ALTER COLUMN "unique_id" SET DEFAULT ((('OUT-'::"text" || "to_char"("now"(), 'YYYYMMDD'::"text")) || '-'::"text") || "lpad"(("nextval"('"public"."outsourcing_profiles_serial_number_seq"'::"regclass"))::"text", 4, '0'::"text"));



ALTER TABLE ONLY "public"."products" ALTER COLUMN "serial_number" SET DEFAULT "nextval"('"public"."products_serial_number_seq"'::"regclass");



ALTER TABLE ONLY "public"."products" ALTER COLUMN "unique_id" SET DEFAULT ((('PRD-'::"text" || "to_char"("now"(), 'YYYYMMDD'::"text")) || '-'::"text") || "lpad"(("nextval"('"public"."products_serial_number_seq"'::"regclass"))::"text", 4, '0'::"text"));



ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_product_id_key" UNIQUE ("product_id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."outsourcing_profiles"
    ADD CONSTRAINT "outsourcing_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_sku_key" UNIQUE ("sku");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."stock_movements"
    ADD CONSTRAINT "stock_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_user_id_key" UNIQUE ("user_id");



CREATE INDEX "idx_activity_logs_created_at" ON "public"."activity_logs" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_activity_logs_user_id" ON "public"."activity_logs" USING "btree" ("user_id");



CREATE INDEX "idx_orders_created_by_email" ON "public"."orders" USING "btree" ("created_by_email");



CREATE INDEX "idx_user_profiles_login_ip" ON "public"."user_profiles" USING "btree" ("login_ip");



CREATE OR REPLACE TRIGGER "trigger_orders_unique_id" BEFORE INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."generate_unique_id_orders"();



CREATE OR REPLACE TRIGGER "trigger_outsourcing_unique_id" BEFORE INSERT ON "public"."outsourcing_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."generate_unique_id_outsourcing"();



CREATE OR REPLACE TRIGGER "trigger_products_unique_id" BEFORE INSERT ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."generate_unique_id_products"();



CREATE OR REPLACE TRIGGER "update_categories_updated_at" BEFORE UPDATE ON "public"."categories" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_inventory_last_updated" BEFORE UPDATE ON "public"."inventory" FOR EACH ROW EXECUTE FUNCTION "public"."update_inventory_timestamp"();



CREATE OR REPLACE TRIGGER "update_orders_updated_at" BEFORE UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_outsourcing_profiles_updated_at" BEFORE UPDATE ON "public"."outsourcing_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_products_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_profiles_updated_at" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_suppliers_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_user_profiles_updated_at" BEFORE UPDATE ON "public"."user_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_outsourcing_id_fkey" FOREIGN KEY ("outsourcing_id") REFERENCES "public"."outsourcing_profiles"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_outsourcing_id_fkey" FOREIGN KEY ("outsourcing_id") REFERENCES "public"."outsourcing_profiles"("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."stock_movements"
    ADD CONSTRAINT "stock_movements_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."user_profiles"
    ADD CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Admins and standard users can manage inventory" ON "public"."inventory" USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role"])));



CREATE POLICY "Admins and standard users can manage orders" ON "public"."orders" USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role"])));



CREATE POLICY "Admins and standard users can manage stock movements" ON "public"."stock_movements" USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role"])));



CREATE POLICY "Admins can manage all profiles" ON "public"."user_profiles" USING (("public"."get_user_role"("auth"."uid"()) = 'admin'::"public"."user_role"));



CREATE POLICY "Admins can manage categories" ON "public"."categories" USING (("public"."get_user_role"("auth"."uid"()) = 'admin'::"public"."user_role"));



CREATE POLICY "Admins can manage outsourcing profiles" ON "public"."outsourcing_profiles" USING (("public"."get_user_role"("auth"."uid"()) = 'admin'::"public"."user_role"));



CREATE POLICY "Admins can manage products" ON "public"."products" USING (("public"."get_user_role"("auth"."uid"()) = 'admin'::"public"."user_role"));



CREATE POLICY "Admins can manage suppliers" ON "public"."suppliers" USING (("public"."get_user_role"("auth"."uid"()) = 'admin'::"public"."user_role"));



CREATE POLICY "Admins can view all activity logs" ON "public"."activity_logs" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = 'admin'::"public"."user_role"));



CREATE POLICY "Authenticated users can insert their own logs" ON "public"."activity_logs" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Only admin and standard users can read orders" ON "public"."orders" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role"])));



CREATE POLICY "Users can insert their own profile" ON "public"."user_profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own profile OR admins can insert any pro" ON "public"."profiles" FOR INSERT WITH CHECK ((("auth"."uid"() = "user_id") OR ("public"."get_user_role"("auth"."uid"()) = 'admin'::"public"."user_role")));



CREATE POLICY "Users can read categories" ON "public"."categories" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role", 'guest'::"public"."user_role"])));



CREATE POLICY "Users can read inventory" ON "public"."inventory" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role", 'guest'::"public"."user_role"])));



CREATE POLICY "Users can read outsourcing profiles" ON "public"."outsourcing_profiles" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role", 'guest'::"public"."user_role"])));



CREATE POLICY "Users can read products" ON "public"."products" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role", 'guest'::"public"."user_role"])));



CREATE POLICY "Users can read stock movements" ON "public"."stock_movements" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role", 'guest'::"public"."user_role"])));



CREATE POLICY "Users can read suppliers" ON "public"."suppliers" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role", 'guest'::"public"."user_role"])));



CREATE POLICY "Users can update their own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own profile" ON "public"."user_profiles" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view all profiles" ON "public"."user_profiles" FOR SELECT USING (("public"."get_user_role"("auth"."uid"()) = ANY (ARRAY['admin'::"public"."user_role", 'standard'::"public"."user_role", 'guest'::"public"."user_role"])));



CREATE POLICY "Users can view their own activity logs" ON "public"."activity_logs" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."activity_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."outsourcing_profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."stock_movements" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_profiles" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."create_user_account"("p_email" "text", "p_password" "text", "p_name" "text", "p_role" "public"."user_role", "p_phone" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_user_account"("p_email" "text", "p_password" "text", "p_name" "text", "p_role" "public"."user_role", "p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_user_account"("p_email" "text", "p_password" "text", "p_name" "text", "p_role" "public"."user_role", "p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_invoice_number"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_invoice_number"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_invoice_number"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_unique_id_orders"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_unique_id_orders"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_unique_id_orders"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_unique_id_outsourcing"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_unique_id_outsourcing"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_unique_id_outsourcing"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_unique_id_products"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_unique_id_products"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_unique_id_products"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_role"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_role"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_role"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_inventory_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_inventory_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_inventory_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_last_login"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_last_login"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_last_login"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";


















GRANT ALL ON TABLE "public"."activity_logs" TO "anon";
GRANT ALL ON TABLE "public"."activity_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."activity_logs" TO "service_role";



GRANT ALL ON TABLE "public"."categories" TO "anon";
GRANT ALL ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT ALL ON TABLE "public"."inventory" TO "anon";
GRANT ALL ON TABLE "public"."inventory" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON SEQUENCE "public"."orders_serial_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."orders_serial_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."orders_serial_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."outsourcing_profiles" TO "anon";
GRANT ALL ON TABLE "public"."outsourcing_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."outsourcing_profiles" TO "service_role";



GRANT ALL ON SEQUENCE "public"."outsourcing_profiles_serial_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."outsourcing_profiles_serial_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."outsourcing_profiles_serial_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON SEQUENCE "public"."products_serial_number_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."products_serial_number_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."products_serial_number_seq" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."stock_movements" TO "anon";
GRANT ALL ON TABLE "public"."stock_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."stock_movements" TO "service_role";



GRANT ALL ON TABLE "public"."suppliers" TO "anon";
GRANT ALL ON TABLE "public"."suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."suppliers" TO "service_role";



GRANT ALL ON TABLE "public"."user_profiles" TO "anon";
GRANT ALL ON TABLE "public"."user_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."user_profiles" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























