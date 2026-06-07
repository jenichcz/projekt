-- =========================================================================
-- KROK 1: Vyčištění starého schématu (ať nevznikají duplicity a konflikty)
-- =========================================================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.check_reservation_conflict(BIGINT, TIMESTAMPTZ, TIMESTAMPTZ, BIGINT);
DROP TABLE IF EXISTS public.reservations;
DROP TABLE IF EXISTS public.resources;
DROP TABLE IF EXISTS public.profiles;

-- =========================================================================
-- KROK 2: Vytvoření všech tabulek se správnými relacemi a typy
-- =========================================================================

-- 1. Tabulka profiles (propojení na interní Supabase Auth)
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT NOT NULL,
    display_name TEXT,
    role TEXT NOT NULL DEFAULT 'student' CHECK (role IN ('student', 'admin')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Tabulka resources (učebny, hardwarové vybavení)
CREATE TABLE public.resources (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('classroom', 'equipment', 'other')),
    description TEXT,
    location TEXT,
    quantity INTEGER NOT NULL DEFAULT 1,
    available BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Tabulka reservations (samotné rezervace uživatelů)
CREATE TABLE public.reservations (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id BIGINT REFERENCES public.resources(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cancelled')),
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =========================================================================
-- KROK 3: Automatické vytvoření profilu po registraci (Trigger)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, display_name, role)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
        'student' -- Každý nový uživatel začíná jako student
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =========================================================================
-- KROK 4: Funkce pro kontrolu kolizí rezervací (Opraveny typy na BIGINT)
-- =========================================================================
CREATE OR REPLACE FUNCTION public.check_reservation_conflict(
    p_resource_id BIGINT,
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_exclude_id BIGINT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.reservations
        WHERE resource_id = p_resource_id
          AND status = 'active'
          AND (id != p_exclude_id OR p_exclude_id IS NULL)
          AND (start_time < p_end_time AND end_time > p_start_time)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =========================================================================
-- KROK 5: Bezpečnost a oprava Row Level Security (RLS)
-- =========================================================================

-- Profiles: Vypínáme RLS, abychom navždy zabránili infinite recursion chybě
ALTER TABLE public.profiles DISABLE ROW LEVEL SECURITY;

-- Resources: Aktivace a bezpečné politiky
ALTER TABLE public.resources ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Všichni vidí zdroje" ON public.resources
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "Pouze admin může manipulovat se zdroji" ON public.resources
    FOR ALL TO authenticated 
    USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
    );

-- Reservations: Aktivace a bezpečné politiky
ALTER TABLE public.reservations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Uživatel vidí své rezervace, admin všechny" ON public.reservations
    FOR SELECT TO authenticated 
    USING (
        user_id = auth.uid() OR
        EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
    );

CREATE POLICY "Uživatelé mohou vytvářet své rezervace" ON public.reservations
    FOR INSERT TO authenticated 
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Uživatel může zrušit svou rezervaci, admin cokoli" ON public.reservations
    FOR UPDATE TO authenticated 
    USING (
        user_id = auth.uid() OR
        EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
    );

CREATE POLICY "Pouze admin může natvrdo mazat rezervace" ON public.reservations
    FOR DELETE TO authenticated 
    USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
    );

-- =========================================================================
-- KROK 6: Výchozí testovací data pro projekt
-- =========================================================================
INSERT INTO public.resources (name, type, description, location, quantity, available) VALUES
('Učebna internetových technologií (104)', 'classroom', 'Velká učebna s projektorem, Cisco a MikroTik routery.', 'Budova A, 1. patro', 1, true),
('Počítačová učebna (212)', 'classroom', 'Malá seminární místnost, vývojová prostředí a DB.', 'Budova B, 2. patro', 1, true),
('Notebook Dell Latitude', 'equipment', 'Dell Latitude pro účely testování aplikací a sítí.', 'Sklad IT', 5, true),
('Projektor Epson', 'equipment', 'Full HD projektor s HDMI k zapůjčení.', 'Sklad AV techniky', 3, true);