# Rezervační systém – DBS Závěrečný projekt

Webová aplikace pro rezervaci učeben a vybavení. Postavena na **Nuxt 4** + **Supabase**.

## Spuštění projektu

### 1. Klonování repozitáře
```bash
git clone https://github.com/TVUJ_USERNAME/rezervacni-system.git
cd rezervacni-system/nuxt-app```

### 2. Instalace závislostí
```bash
npm install
```

### 3. Nastavení prostředí
V kořenu složky nuxt-app vytvoř nový soubor s názvem .env a doplň do něj své hodnoty ze Supabase → Url a Key:
```env
SUPABASE_URL=https://TVUJ_PROJEKT.supabase.co
SUPABASE_KEY=tvuj_anon_public_klic
```

### 4. Databázové schéma
V Supabase SQL Editoru spusť celý soubor `supabase_schema.sql`.

### 5. První admin
Po registraci prvního účtu spusť v SQL Editoru:
```sql
UPDATE public.profiles SET role = 'admin' WHERE email = 'tvuj@email.cz';
```

### 6. Spuštění vývojového serveru
```bash
npm run dev
```
Aplikace běží na `http://localhost:3000`

---

## Struktura projektu
```
nuxt-app/
├── app/                        # Zdrojový kód aplikace (Nuxt 4 Core)
│   ├── assets/css/main.css     # Globální Tailwind styly
│   ├── components/
│   │   └── AppNavbar.vue       # Hlavní navigační lišta
│   ├── composables/
│   │   ├── useProfile.ts       # Správa stavu uživatele a načítání rolí
│   │   ├── useResources.ts     # Klientská logika pro CRUD operace zdrojů
│   │   └── useReservations.ts  # Logika rezervací a kontrola časových kolizí
│   ├── middleware/
│   │   ├── auth.ts             # Ochrana tras (přístup pouze pro přihlášené / adminy)
│   │   └── guest.ts            # Přesměrování již přihlášených uživatelů z login/register
│   └── pages/
│       ├── reserve/
│       │   └── [id].vue        # Dynamický formulář pro novou rezervaci konkrétního zdroje
│       ├── admin.vue           # Administrační panel (Správa uživatelů a práv)
│       ├── index.vue           # Úvodní přehledová stránka / Dashboard
│       ├── login.vue           # Přihlašovací formulář
│       ├── register.vue        # Registrační formulář (student / admin)
│       ├── reservations.vue    # Přehled mých rezervací (student) / všech rezervací (admin)
│       └── resources.vue       # Seznam zdrojů s integrovaným filtrem a CRUD managementem
├── public/                     # Statické soubory
├── nuxt.config.ts              # Konfigurace Nuxtu (aktivován compatibilityVersion: 4)
├── supabase_schema.sql         # Kompletní SQL skript pro inicializaci databáze
└── tsconfig.json               # Konfigurace TypeScriptu
```

## Databázové schéma

### `profiles`
| Sloupec | Typ | Popis |
|---|---|---|
| id | UUID | Primární klíč (FK → auth.users.id) |
| email | TEXT | E-mail uživatele |
| display_name | TEXT | Zobrazované jméno |
| role | TEXT | Uživatelská role (`student` nebo `admin`) |
| created_at | TIMESTAMPTZ | Datum vytvoření |

### `resources`
| Sloupec | Typ | Popis |
|---|---|---|
| id | BIGINT | Primární klíč (Generováno automaticky) |
| name | TEXT | Název zdroje (učebna, hardwarové vybavení) |
| type | TEXT | Typ zdroje (`classroom`, `equipment`, `other`) |
| description | TEXT | Bližší popis |
| location | TEXT | Fyzické umístění |
| quantity | INTEGER | Celkový počet kusů |
| available | BOOLEAN | Příznak celkové dostupnosti |
| created_at | TIMESTAMPTZ | Datum vytvoření |

### `reservations`
| Sloupec | Typ | Popis |
|---|---|---|
| id | BIGINT | Primární klíč (Generováno automaticky) |
| resource_id | BIGINT | Cizí klíč (FK → public.resources.id) |
| user_id | UUID | Cizí klíč (FK → public.profiles.id) |
| start_time | TIMESTAMPTZ | Začátek rezervace |
| end_time | TIMESTAMPTZ | Konec rezervace |
| status | TEXT | Stav rezervace (`active` nebo `cancelled`) |
| note | TEXT | Volitelná poznámka uživatele |
| created_at | TIMESTAMPTZ | Datum vytvoření záznamu |

---

## API volání (Supabase klient)

| Operace | Kód |
|---|---|
| Načíst zdroje | `supabase.from('resources').select('*')` |
| Přidat zdroj | `supabase.from('resources').insert(data)` |
| Upravit zdroj | `supabase.from('resources').update(data).eq('id', id)` |
| Smazat zdroj | `supabase.from('resources').delete().eq('id', id)` |
| Načíst rezervace | `supabase.from('reservations').select('*, resources(*), profiles(*)')` |
| Vytvořit rezervaci | `supabase.from('reservations').insert(data)` |
| Kontrola kolize | `supabase.rpc('check_reservation_conflict', {...})` |
| Zrušit rezervaci | `supabase.from('reservations').update({status:'cancelled'}).eq('id', id)` |
| Přihlášení | `supabase.auth.signInWithPassword({email, password})` |
| Registrace | `supabase.auth.signUp({email, password, options})` |
| Odhlášení | `supabase.auth.signOut()` |

---

## Bezpečnost (Row Level Security)
- **profiles**: RLS je z důvodu rekurzivního zacyklení (infinite recursion) v databázi vypnuto. Data jsou zabezpečena přímo na úrovni aplikace v Nuxt middleware.
- **resources**: Čtení je povoleno pro všechny přihlášené uživatele. Operace zápisu, úpravy a mazání jsou striktně omezeny pouze na administrátory.
- **reservations**: Běžný uživatel (student) vidí a upravuje pouze své vlastní rezervace na základě porovnání jeho `auth.uid()`. Administrátor má přístup ke všem záznamům.

---

## Testovací scénáře

| # | Scénář | Očekávaný výsledek |
|---|---|---|
| 1 | Registrace nového uživatele | Profil úspěšně vytvořen v DB, databázový trigger automaticky nastaví výchozí roli na `student`. |
| 2 | Přihlášení se špatným heslem | Supabase Auth odmítne požadavek, rozhraní zachytí chybu a uživateli se zobrazí chybová hláška. |
| 3 | Student vytvoří novou rezervaci | Pokud zvolený čas nekoliduje, data se bezpečně zapíší a uživatel vidí potvrzení. |
| 4 | Pokus o rezervaci na již obsazený čas | Systém přes RPC funkci detekuje překryv časů, operaci zamítne a vyhodnotí stav jako kolizi. |
| 5 | Student se pokusit smazat nebo upravit zdroj | Databázová politika RLS operaci zablokuje a vrátí chybový stav. |
| 6 | Administrátor upravuje parametry zdroje | Data se okamžitě přepíší v DB a reaktivně se aktualizují všem uživatelům na úvodní stránce. |
| 7 | Filtrace a vyhledávání v seznamu zdrojů | Klientská aplikace okamžitě redukuje zobrazené položky podle vybraného typu nebo textového řetězce. |

---

## Known Limitations (Známá omezení)
- **E-mailové potvrzení**: Globální ověřování e-mailů (Double Opt-In) je v nastavení Supabase Auth vypnuté pro usnadnění lokálního testování (uživatel je aktivní ihned po registraci).
- **Množstevní kolize**: Kontrola kolizí hlídá rezervaci jako absolutní blokaci konkrétního kusu (`resource_id`). Pokročilá logika pro dělení kapacity (pokud je na skladě více kusů pod stejným ID) není předmětem tohoto zadání.
- **Notifikace**: V aplikaci nejsou implementována automatická upozornění (např. e-mailové připomenutí blížícího se konce rezervace).