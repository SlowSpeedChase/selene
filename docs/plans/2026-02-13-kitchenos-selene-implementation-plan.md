# KitchenOS-Selene Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Index KitchenOS recipes into Selene's database and enable conversational meal planning through SeleneChat's thinking partner.

**Architecture:** Selene reads the KitchenOS Obsidian vault via a scheduled TypeScript workflow, stores recipes in SQLite, and SeleneChat queries them through a new meal planning query type with specialized context/prompt builders. Meal plans export back to Obsidian in KitchenOS-native format.

**Tech Stack:** TypeScript (workflow), Swift/SwiftUI (SeleneChat), SQLite (database), Ollama/mistral:7b (LLM)

**Design Doc:** `docs/plans/2026-02-13-kitchenos-selene-integration-design.md`

---

## Phase 1: Recipe Indexer (Backend)

### Task 1: Database Migration

**Files:**
- Create: `database/migrations/019_kitchenos_recipes.sql`

**Step 1: Write the migration SQL**

```sql
-- 019_kitchenos_recipes.sql
-- KitchenOS recipe integration tables.
-- Stores recipes indexed from KitchenOS Obsidian vault,
-- meal plans created via SeleneChat, and shopping lists.

CREATE TABLE IF NOT EXISTS recipes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  content_hash TEXT UNIQUE NOT NULL,
  source_url TEXT,
  source_channel TEXT,
  file_path TEXT NOT NULL,
  servings INTEGER,
  prep_time_minutes INTEGER,
  cook_time_minutes INTEGER,
  difficulty TEXT CHECK(difficulty IN ('easy', 'medium', 'hard')),
  cuisine TEXT,
  protein TEXT,
  dish_type TEXT,
  meal_occasions TEXT,
  dietary TEXT,
  ingredients TEXT NOT NULL,
  calories INTEGER,
  nutrition_protein INTEGER,
  carbs INTEGER,
  fat INTEGER,
  indexed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  status TEXT DEFAULT 'active' CHECK(status IN ('active', 'archived')),
  test_run TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_recipes_content_hash ON recipes(content_hash);
CREATE INDEX IF NOT EXISTS idx_recipes_status ON recipes(status);
CREATE INDEX IF NOT EXISTS idx_recipes_cuisine ON recipes(cuisine);
CREATE INDEX IF NOT EXISTS idx_recipes_protein ON recipes(protein);
CREATE INDEX IF NOT EXISTS idx_recipes_test_run ON recipes(test_run);

CREATE TABLE IF NOT EXISTS meal_plans (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  week TEXT NOT NULL UNIQUE,
  status TEXT DEFAULT 'draft' CHECK(status IN ('draft', 'active', 'completed')),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT,
  exported_at TEXT,
  test_run TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_meal_plans_week ON meal_plans(week);
CREATE INDEX IF NOT EXISTS idx_meal_plans_status ON meal_plans(status);

CREATE TABLE IF NOT EXISTS meal_plan_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meal_plan_id INTEGER NOT NULL,
  day TEXT NOT NULL CHECK(day IN ('monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday')),
  meal TEXT NOT NULL CHECK(meal IN ('breakfast', 'lunch', 'dinner')),
  recipe_id INTEGER,
  recipe_title TEXT NOT NULL,
  notes TEXT,
  FOREIGN KEY (meal_plan_id) REFERENCES meal_plans(id) ON DELETE CASCADE,
  FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE SET NULL,
  UNIQUE(meal_plan_id, day, meal)
);

CREATE INDEX IF NOT EXISTS idx_meal_plan_items_plan ON meal_plan_items(meal_plan_id);

CREATE TABLE IF NOT EXISTS shopping_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  meal_plan_id INTEGER NOT NULL,
  ingredient TEXT NOT NULL,
  amount REAL,
  unit TEXT,
  category TEXT CHECK(category IN ('produce', 'dairy', 'meat', 'pantry', 'frozen', 'bakery', 'other')),
  checked INTEGER DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (meal_plan_id) REFERENCES meal_plans(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_shopping_items_plan ON shopping_items(meal_plan_id);
```

**Step 2: Apply migration**

Run: `sqlite3 data/selene.db < database/migrations/019_kitchenos_recipes.sql`
Expected: No output (success). Verify: `sqlite3 data/selene.db ".tables" | grep recipes`

**Step 3: Commit**

```bash
git add database/migrations/019_kitchenos_recipes.sql
git commit -m "feat(db): add recipe, meal plan, and shopping list tables (migration 019)"
```

---

### Task 2: Config — Add KitchenOS Vault Path

**Files:**
- Modify: `src/lib/config.ts`

**Step 1: Read config.ts and understand the pattern**

Read `src/lib/config.ts` to find the config export object and path resolution pattern.

**Step 2: Add KitchenOS vault path to config**

Add a `kitchenOsVaultPath` getter function and export it in the config object. Follow the existing pattern:
- Check `process.env.KITCHENOS_VAULT_PATH` first
- Test environment falls back to `join(projectRoot, 'data-test/kitchenos-vault')`
- Production defaults to the iCloud Obsidian vault path: `join(homedir(), 'Library/Mobile Documents/iCloud~md~obsidian/Documents/KitchenOS')`

Add to the config export:
```typescript
kitchenOsVaultPath: getKitchenOsVaultPath(),
```

**Step 3: Verify no TypeScript errors**

Run: `cd /Users/chaseeasterling/selene && npx tsc --noEmit src/lib/config.ts`
Expected: No errors

**Step 4: Commit**

```bash
git add src/lib/config.ts
git commit -m "feat(config): add KitchenOS vault path configuration"
```

---

### Task 3: Recipe Parser Module

**Files:**
- Create: `src/lib/recipe-parser.ts`
- Create: `src/lib/recipe-parser.test.ts`

**Step 1: Write the failing test**

Create `src/lib/recipe-parser.test.ts`:

```typescript
import assert from 'assert';
import { parseRecipeFrontmatter, parseRecipeCookingMode } from './recipe-parser';

async function runTests() {
  console.log('Recipe Parser Tests\n');

  // Test 1: Parse YAML frontmatter recipe
  console.log('Test 1: Parses YAML frontmatter recipe');
  {
    const content = `---
title: Pasta Carbonara
source_url: https://youtube.com/watch?v=test123
source_channel: Binging with Babish
servings: 4
prep_time: 10 min
cook_time: 20 min
difficulty: medium
cuisine: Italian
protein: pork
dish_type: pasta
meal_occasion:
  - weeknight-dinner
dietary:
  - contains-gluten
calories: 580
nutrition_protein: 25
carbs: 65
fat: 22
---

# Pasta Carbonara

> Classic Roman pasta with eggs, cheese, and guanciale.

## Ingredients

| Amount | Unit | Ingredient |
|--------|------|------------|
| 400 | g | spaghetti |
| 200 | g | guanciale |
| 4 | whole | egg yolks |
| 100 | g | pecorino romano |
`;

    const recipe = parseRecipeFrontmatter(content, 'Recipes/Pasta Carbonara.md');
    assert.strictEqual(recipe.title, 'Pasta Carbonara');
    assert.strictEqual(recipe.source_url, 'https://youtube.com/watch?v=test123');
    assert.strictEqual(recipe.servings, 4);
    assert.strictEqual(recipe.prep_time_minutes, 10);
    assert.strictEqual(recipe.cook_time_minutes, 20);
    assert.strictEqual(recipe.cuisine, 'Italian');
    assert.strictEqual(recipe.protein, 'pork');
    assert.strictEqual(recipe.file_path, 'Recipes/Pasta Carbonara.md');
    const ingredients = JSON.parse(recipe.ingredients);
    assert.strictEqual(ingredients.length, 4);
    assert.strictEqual(ingredients[0].item, 'spaghetti');
    console.log('  PASS');
  }

  // Test 2: Parse time string into minutes
  console.log('Test 2: Parses time strings into minutes');
  {
    const content = `---
title: Quick Soup
prep_time: 5 min
cook_time: 1 hour 30 min
servings: 2
---
## Ingredients
| Amount | Unit | Ingredient |
| 1 | can | tomatoes |
`;
    const recipe = parseRecipeFrontmatter(content, 'Recipes/Quick Soup.md');
    assert.strictEqual(recipe.prep_time_minutes, 5);
    assert.strictEqual(recipe.cook_time_minutes, 90);
    console.log('  PASS');
  }

  // Test 3: Parse Cooking Mode format (no frontmatter)
  console.log('Test 3: Parses Cooking Mode format');
  {
    const content = `# Butter Biscuits

> Flaky, buttery biscuits.

*breakfast, baking* **8 servings**

---

- *2 cups* all-purpose flour
- *1 tbsp* baking powder
- *1/2 cup* cold butter

---

1. Mix dry ingredients
2. Cut in butter
3. Bake at 425F

*Source: [Butter Biscuits](https://example.com) by Test Channel*
`;
    const recipe = parseRecipeCookingMode(content, 'Recipes/Cooking Mode/Butter Biscuits.recipe.md');
    assert.strictEqual(recipe.title, 'Butter Biscuits');
    assert.strictEqual(recipe.file_path, 'Recipes/Cooking Mode/Butter Biscuits.recipe.md');
    const ingredients = JSON.parse(recipe.ingredients);
    assert.strictEqual(ingredients.length, 3);
    assert.strictEqual(ingredients[0].item, 'all-purpose flour');
    console.log('  PASS');
  }

  // Test 4: Content hash is deterministic
  console.log('Test 4: Content hash is deterministic');
  {
    const content = `---
title: Test
servings: 1
---
## Ingredients
| Amount | Unit | Ingredient |
| 1 | cup | water |
`;
    const r1 = parseRecipeFrontmatter(content, 'test.md');
    const r2 = parseRecipeFrontmatter(content, 'test.md');
    assert.strictEqual(r1.content_hash, r2.content_hash);
    console.log('  PASS');
  }

  console.log('\nAll recipe parser tests passed!');
}

runTests().catch(err => {
  console.error('\nTest failed:', err.message);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/lib/recipe-parser.test.ts`
Expected: FAIL — `Cannot find module './recipe-parser'`

**Step 3: Write the recipe parser implementation**

Create `src/lib/recipe-parser.ts`:

The module should export:
- `parseRecipeFrontmatter(content: string, filePath: string): RecipeRow` — parses files with YAML frontmatter
- `parseRecipeCookingMode(content: string, filePath: string): RecipeRow` — parses Cooking Mode format files (no frontmatter, uses `*amount unit* ingredient` pattern)
- `parseTimeToMinutes(timeStr: string): number | null` — converts "10 min", "1 hour 30 min" to integer minutes

`RecipeRow` interface matches the `recipes` table columns:
```typescript
export interface RecipeRow {
  title: string;
  content_hash: string;
  source_url: string | null;
  source_channel: string | null;
  file_path: string;
  servings: number | null;
  prep_time_minutes: number | null;
  cook_time_minutes: number | null;
  difficulty: string | null;
  cuisine: string | null;
  protein: string | null;
  dish_type: string | null;
  meal_occasions: string | null;  // JSON array
  dietary: string | null;         // JSON array
  ingredients: string;            // JSON array of {amount, unit, item}
  calories: number | null;
  nutrition_protein: number | null;
  carbs: number | null;
  fat: number | null;
}
```

Implementation details:
- Use `createHash('sha256')` from `crypto` for content_hash (same as raw_notes pattern)
- Parse YAML frontmatter between `---` delimiters manually (split on `---`, parse key-value pairs) or use a simple YAML parser
- Parse ingredient table: regex for `| amount | unit | ingredient |` rows
- Parse Cooking Mode ingredients: regex for `- *amount unit* ingredient` pattern
- `parseTimeToMinutes`: handle "X min", "X hour", "X hour Y min", "Xh Ym" patterns

**Step 4: Run tests to verify they pass**

Run: `npx ts-node src/lib/recipe-parser.test.ts`
Expected: All 4 tests PASS

**Step 5: Commit**

```bash
git add src/lib/recipe-parser.ts src/lib/recipe-parser.test.ts
git commit -m "feat: add recipe parser for KitchenOS frontmatter and Cooking Mode formats"
```

---

### Task 4: Index Recipes Workflow

**Files:**
- Create: `src/workflows/index-recipes.ts`
- Create: `src/workflows/index-recipes.test.ts`

**Step 1: Write the failing test**

Create `src/workflows/index-recipes.test.ts`:

```typescript
import assert from 'assert';
import Database from 'better-sqlite3';
import { mkdirSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';

// Test with a temporary vault directory
const TEST_VAULT = join(__dirname, '../../data-test/kitchenos-vault-test');
const TEST_DB = ':memory:';

async function runTests() {
  console.log('Index Recipes Workflow Tests\n');

  // Setup: create temp vault with recipe files
  rmSync(TEST_VAULT, { recursive: true, force: true });
  mkdirSync(join(TEST_VAULT, 'Recipes'), { recursive: true });
  mkdirSync(join(TEST_VAULT, 'Recipes/Cooking Mode'), { recursive: true });
  mkdirSync(join(TEST_VAULT, 'Meal Plans'), { recursive: true });

  // Write a frontmatter recipe
  writeFileSync(join(TEST_VAULT, 'Recipes/Test Pasta.md'), `---
title: Test Pasta
source_url: https://youtube.com/watch?v=abc
servings: 4
prep_time: 15 min
cook_time: 20 min
difficulty: easy
cuisine: Italian
protein: null
dish_type: pasta
---

## Ingredients

| Amount | Unit | Ingredient |
|--------|------|------------|
| 400 | g | pasta |
| 2 | cloves | garlic |
`);

  // Write a cooking mode recipe
  writeFileSync(join(TEST_VAULT, 'Recipes/Cooking Mode/Quick Rice.recipe.md'), `# Quick Rice

> Simple steamed rice.

*side-dish* **4 servings**

---

- *2 cups* rice
- *3 cups* water

---

1. Rinse rice
2. Cook in water
`);

  // Write a meal plan
  writeFileSync(join(TEST_VAULT, 'Meal Plans/2026-W07.md'), `# Meal Plan - Week 07 (Feb 10 - Feb 16)

## Monday (2026-02-10)
### Breakfast
Oatmeal

### Lunch
[[Test Pasta]]

### Dinner
[[Quick Rice]]
`);

  // Tests will import and call the workflow function
  // For now, verify the parser integration works at file level
  console.log('Test 1: Scans vault and finds recipe files');
  // ... test that scanVault returns correct file list

  console.log('Test 2: Indexes new recipes (insert)');
  // ... test that new recipes are inserted into DB

  console.log('Test 3: Skips unchanged recipes (content_hash match)');
  // ... test that re-running doesn't duplicate

  console.log('Test 4: Updates changed recipes');
  // ... test that modified file content triggers update

  console.log('Test 5: Indexes existing meal plans');
  // ... test that meal plan files populate meal_plans + meal_plan_items

  // Cleanup
  rmSync(TEST_VAULT, { recursive: true, force: true });
  console.log('\nAll index-recipes tests passed!');
}

runTests().catch(err => {
  console.error('\nTest failed:', err.message);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/workflows/index-recipes.test.ts`
Expected: FAIL — module not found or function not defined

**Step 3: Write the index-recipes workflow**

Create `src/workflows/index-recipes.ts` following the workflow boilerplate pattern:

```typescript
import { readdirSync, readFileSync, existsSync } from 'fs';
import { join, relative } from 'path';
import { createWorkflowLogger, db, config } from '../lib';
import { parseRecipeFrontmatter, parseRecipeCookingMode } from '../lib/recipe-parser';
import type { WorkflowResult } from '../types';

const log = createWorkflowLogger('index-recipes');
```

Key functions:
- `scanRecipeFiles(vaultPath: string): string[]` — recursively find `.md` files in `Recipes/` directory
- `indexRecipes(vaultPath?: string): Promise<WorkflowResult>` — main workflow function:
  1. Scan vault for recipe `.md` files
  2. For each file: read content, detect format (frontmatter vs cooking mode), parse
  3. Check content_hash against DB — skip if unchanged
  4. Upsert: INSERT or UPDATE based on content_hash
  5. Return WorkflowResult with counts
- `indexMealPlans(vaultPath?: string): Promise<WorkflowResult>` — index meal plan files:
  1. Scan `Meal Plans/` for `.md` files
  2. Parse week from filename (e.g., `2026-W07.md`)
  3. Parse day sections and extract `[[Recipe Name]]` wiki links
  4. Resolve recipe links to recipe IDs where possible
  5. Insert into meal_plans + meal_plan_items

CLI entry point calls both `indexRecipes()` and `indexMealPlans()`.

SQL patterns:
```sql
-- Check if recipe exists
SELECT id, content_hash FROM recipes WHERE file_path = ? AND test_run IS NULL

-- Insert new recipe
INSERT INTO recipes (title, content_hash, source_url, source_channel, file_path,
  servings, prep_time_minutes, cook_time_minutes, difficulty, cuisine, protein,
  dish_type, meal_occasions, dietary, ingredients, calories, nutrition_protein,
  carbs, fat, indexed_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)

-- Update changed recipe
UPDATE recipes SET title=?, content_hash=?, source_url=?, source_channel=?,
  servings=?, prep_time_minutes=?, cook_time_minutes=?, difficulty=?, cuisine=?,
  protein=?, dish_type=?, meal_occasions=?, dietary=?, ingredients=?, calories=?,
  nutrition_protein=?, carbs=?, fat=?, updated_at=?
WHERE file_path = ? AND test_run IS NULL

-- Resolve recipe link to ID
SELECT id FROM recipes WHERE title = ? AND test_run IS NULL
```

**Step 4: Run tests to verify they pass**

Run: `npx ts-node src/workflows/index-recipes.test.ts`
Expected: All 5 tests PASS

**Step 5: Run manually against real vault**

Run: `npx ts-node src/workflows/index-recipes.ts`
Expected: Logs showing recipes found and indexed. Verify: `sqlite3 data/selene.db "SELECT COUNT(*), title FROM recipes GROUP BY title LIMIT 5;"`

**Step 6: Commit**

```bash
git add src/workflows/index-recipes.ts src/workflows/index-recipes.test.ts
git commit -m "feat: add index-recipes workflow to scan KitchenOS vault"
```

---

### Task 5: Register in WorkflowScheduler

**Files:**
- Modify: `SeleneChat/Sources/Models/ScheduledWorkflow.swift`

**Step 1: Read the file to find the allWorkflows array**

Read `SeleneChat/Sources/Models/ScheduledWorkflow.swift` and locate the `static let allWorkflows` array.

**Step 2: Add index-recipes entry**

Add to the `allWorkflows` array:
```swift
ScheduledWorkflow(
    id: "index-recipes",
    name: "Index Recipes",
    scriptPath: "src/workflows/index-recipes.ts",
    schedule: .interval(1800),  // Every 30 minutes
    usesOllama: false
),
```

**Step 3: Build SeleneChat to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add SeleneChat/Sources/Models/ScheduledWorkflow.swift
git commit -m "feat: register index-recipes in WorkflowScheduler (30 min interval)"
```

---

### Task 6: Export recipe-parser from lib barrel

**Files:**
- Modify: `src/lib/index.ts` (if barrel export exists)

**Step 1: Check if there's a barrel export**

Read `src/lib/index.ts`. If it exists and re-exports modules, add recipe-parser. If workflows import directly from `../lib/recipe-parser`, skip this task.

**Step 2: Add export if needed**

```typescript
export { parseRecipeFrontmatter, parseRecipeCookingMode } from './recipe-parser';
```

**Step 3: Commit if changed**

```bash
git add src/lib/index.ts
git commit -m "feat: export recipe parser from lib barrel"
```

---

## Phase 2: SeleneChat Meal Planning Chat

### Task 7: Recipe Model

**Files:**
- Create: `SeleneChat/Sources/Models/Recipe.swift`
- Create: `SeleneChat/Tests/SeleneChatTests/Models/RecipeTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Models/RecipeTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class RecipeTests: XCTestCase {

    func testRecipeInitialization() {
        let recipe = Recipe(
            id: 1,
            title: "Pasta Carbonara",
            filePath: "Recipes/Pasta Carbonara.md",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 20,
            difficulty: "medium",
            cuisine: "Italian",
            protein: "pork",
            dishType: "pasta",
            mealOccasions: ["weeknight-dinner"],
            dietary: ["contains-gluten"],
            ingredients: [
                Recipe.Ingredient(amount: "400", unit: "g", item: "spaghetti"),
                Recipe.Ingredient(amount: "200", unit: "g", item: "guanciale")
            ],
            calories: 580
        )

        XCTAssertEqual(recipe.id, 1)
        XCTAssertEqual(recipe.title, "Pasta Carbonara")
        XCTAssertEqual(recipe.servings, 4)
        XCTAssertEqual(recipe.totalTimeMinutes, 30)
        XCTAssertEqual(recipe.ingredients.count, 2)
    }

    func testTotalTimeWithNilValues() {
        let recipe = Recipe(
            id: 1, title: "Test", filePath: "test.md",
            servings: nil, prepTimeMinutes: nil, cookTimeMinutes: 15,
            difficulty: nil, cuisine: nil, protein: nil, dishType: nil,
            mealOccasions: [], dietary: [], ingredients: [], calories: nil
        )
        XCTAssertEqual(recipe.totalTimeMinutes, 15)
    }

    func testCompactDescription() {
        let recipe = Recipe(
            id: 1, title: "Quick Stir Fry", filePath: "test.md",
            servings: 2, prepTimeMinutes: 5, cookTimeMinutes: 10,
            difficulty: "easy", cuisine: "Asian", protein: "chicken",
            dishType: "stir-fry",
            mealOccasions: ["weeknight-dinner", "meal-prep"],
            dietary: [], ingredients: [], calories: 350
        )
        let desc = recipe.compactDescription
        XCTAssertTrue(desc.contains("Quick Stir Fry"))
        XCTAssertTrue(desc.contains("15 min"))
        XCTAssertTrue(desc.contains("Asian"))
        XCTAssertTrue(desc.contains("chicken"))
    }

    func testMockFactory() {
        let recipe = Recipe.mock()
        XCTAssertEqual(recipe.id, 1)
        XCTAssertFalse(recipe.title.isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter RecipeTests 2>&1 | head -20`
Expected: FAIL — `cannot find type 'Recipe' in scope`

**Step 3: Write the Recipe model**

Create `SeleneChat/Sources/Models/Recipe.swift`:

```swift
import Foundation

struct Recipe: Identifiable, Hashable {
    let id: Int64
    let title: String
    let filePath: String
    let servings: Int?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let difficulty: String?
    let cuisine: String?
    let protein: String?
    let dishType: String?
    let mealOccasions: [String]
    let dietary: [String]
    let ingredients: [Ingredient]
    let calories: Int?

    struct Ingredient: Hashable, Codable {
        let amount: String?
        let unit: String?
        let item: String
    }

    var totalTimeMinutes: Int? {
        switch (prepTimeMinutes, cookTimeMinutes) {
        case let (prep?, cook?): return prep + cook
        case let (prep?, nil): return prep
        case let (nil, cook?): return cook
        case (nil, nil): return nil
        }
    }

    /// Compact one-line description for LLM context (low token cost)
    var compactDescription: String {
        var parts: [String] = [title]
        if let time = totalTimeMinutes { parts.append("\(time) min") }
        if let cuisine = cuisine { parts.append(cuisine) }
        if let protein = protein { parts.append(protein) }
        if let servings = servings { parts.append("\(servings) servings") }
        if let calories = calories { parts.append("\(calories) cal") }
        if !mealOccasions.isEmpty { parts.append(mealOccasions.joined(separator: ", ")) }
        return parts.joined(separator: " | ")
    }

    #if DEBUG
    static func mock(
        id: Int64 = 1,
        title: String = "Test Recipe",
        filePath: String = "Recipes/Test.md",
        servings: Int? = 4,
        prepTimeMinutes: Int? = 10,
        cookTimeMinutes: Int? = 20,
        cuisine: String? = "Italian",
        protein: String? = "chicken",
        ingredients: [Ingredient] = [Ingredient(amount: "1", unit: "cup", item: "rice")]
    ) -> Recipe {
        Recipe(
            id: id, title: title, filePath: filePath,
            servings: servings, prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes, difficulty: "easy",
            cuisine: cuisine, protein: protein, dishType: "main",
            mealOccasions: ["weeknight-dinner"], dietary: [],
            ingredients: ingredients, calories: 400
        )
    }
    #endif
}
```

**Step 4: Run tests to verify they pass**

Run: `cd SeleneChat && swift test --filter RecipeTests`
Expected: All 4 tests PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Models/Recipe.swift SeleneChat/Tests/SeleneChatTests/Models/RecipeTests.swift
git commit -m "feat(model): add Recipe model with ingredients and compact description"
```

---

### Task 8: DatabaseService — Recipe Query Methods

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift`
- Create: `SeleneChat/Tests/SeleneChatTests/Services/RecipeQueryTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Services/RecipeQueryTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class RecipeQueryTests: XCTestCase {

    @MainActor
    func testGetAllRecipesReturnsEmptyForNoData() async throws {
        let db = DatabaseService.shared
        let recipes = try await db.getAllRecipes()
        // May or may not be empty depending on DB state
        // Just verify it doesn't crash and returns [Recipe]
        XCTAssertNotNil(recipes)
    }

    @MainActor
    func testGetRecipesByProteinReturnsArray() async throws {
        let db = DatabaseService.shared
        let recipes = try await db.getRecipesByProtein("chicken")
        XCTAssertNotNil(recipes)
    }

    @MainActor
    func testGetRecentMealPlansReturnsArray() async throws {
        let db = DatabaseService.shared
        let plans = try await db.getRecentMealPlans(weeks: 3)
        XCTAssertNotNil(plans)
    }

    @MainActor
    func testGetRecipeByIdReturnsNilForMissing() async throws {
        let db = DatabaseService.shared
        let recipe = try await db.getRecipeById(99999)
        XCTAssertNil(recipe)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter RecipeQueryTests 2>&1 | head -20`
Expected: FAIL — method `getAllRecipes` not found on DatabaseService

**Step 3: Add recipe query methods to DatabaseService**

Add to `DatabaseService.swift`:

```swift
// MARK: - Recipe Queries

func getAllRecipes(limit: Int = 200) async throws -> [Recipe] {
    // Query recipes table, parse JSON fields (ingredients, meal_occasions, dietary)
    // ORDER BY title ASC
}

func getRecipesByProtein(_ protein: String, limit: Int = 50) async throws -> [Recipe] {
    // WHERE protein = ? AND status = 'active' AND test_run IS NULL
}

func getRecipesByCuisine(_ cuisine: String, limit: Int = 50) async throws -> [Recipe] {
    // WHERE cuisine = ? AND status = 'active' AND test_run IS NULL
}

func getRecipeById(_ id: Int64) async throws -> Recipe? {
    // WHERE id = ? AND test_run IS NULL
}

func searchRecipes(query: String, limit: Int = 50) async throws -> [Recipe] {
    // WHERE title LIKE '%query%' OR ingredients LIKE '%query%'
    // AND status = 'active' AND test_run IS NULL
}

// MARK: - Meal Plan Queries

func getRecentMealPlans(weeks: Int = 3) async throws -> [(week: String, items: [(day: String, meal: String, recipeTitle: String)])] {
    // JOIN meal_plans mp ON mpi.meal_plan_id = mp.id
    // WHERE mp.test_run IS NULL
    // ORDER BY mp.week DESC LIMIT ?
}

func getMealPlanForWeek(_ week: String) async throws -> [(day: String, meal: String, recipeTitle: String)] {
    // WHERE mp.week = ? AND mp.test_run IS NULL
}
```

Parse JSON fields using `JSONDecoder` for ingredients, or manual parsing for simple arrays. Follow the pattern used for `concepts` and `secondary_themes` in existing note queries.

**Step 4: Run tests to verify they pass**

Run: `cd SeleneChat && swift test --filter RecipeQueryTests`
Expected: All 4 tests PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/DatabaseService.swift SeleneChat/Tests/SeleneChatTests/Services/RecipeQueryTests.swift
git commit -m "feat(db): add recipe and meal plan query methods to DatabaseService"
```

---

### Task 9: QueryAnalyzer — Meal Planning Detection

**Files:**
- Modify: `SeleneChat/Sources/Services/QueryAnalyzer.swift`
- Create: `SeleneChat/Tests/SeleneChatTests/Services/MealPlanningQueryTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Services/MealPlanningQueryTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class MealPlanningQueryTests: XCTestCase {

    func testDetectsMealPlanQuery() {
        let analyzer = QueryAnalyzer()
        XCTAssertEqual(analyzer.detectQueryType("help me plan next week's meals"), .mealPlanning)
    }

    func testDetectsWhatShouldICook() {
        let analyzer = QueryAnalyzer()
        XCTAssertEqual(analyzer.detectQueryType("what should I cook tonight"), .mealPlanning)
    }

    func testDetectsGroceryList() {
        let analyzer = QueryAnalyzer()
        XCTAssertEqual(analyzer.detectQueryType("what do I need for my grocery list"), .mealPlanning)
    }

    func testDetectsDinnerIdeas() {
        let analyzer = QueryAnalyzer()
        XCTAssertEqual(analyzer.detectQueryType("give me some dinner ideas for the week"), .mealPlanning)
    }

    func testDetectsMealPrep() {
        let analyzer = QueryAnalyzer()
        XCTAssertEqual(analyzer.detectQueryType("what should I meal prep this sunday"), .mealPlanning)
    }

    func testDoesNotFalsePositiveOnFood() {
        let analyzer = QueryAnalyzer()
        // "food" alone shouldn't trigger meal planning if it's in a note context
        let result = analyzer.detectQueryType("show me notes about food")
        XCTAssertNotEqual(result, .mealPlanning)
    }

    func testDoesNotFalsePositiveOnGeneral() {
        let analyzer = QueryAnalyzer()
        let result = analyzer.detectQueryType("how am I doing today")
        XCTAssertNotEqual(result, .mealPlanning)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter MealPlanningQueryTests 2>&1 | head -20`
Expected: FAIL — `.mealPlanning` not found

**Step 3: Add mealPlanning to QueryAnalyzer**

Modify `QueryAnalyzer.swift`:

1. Add `case mealPlanning` to `QueryType` enum
2. Add meal planning indicators array:
   ```swift
   private let mealPlanningIndicators = [
       "meal plan", "what should i cook", "what should i eat",
       "dinner ideas", "lunch ideas", "breakfast ideas",
       "plan next week", "plan this week", "meal prep",
       "grocery list", "shopping list", "what to cook",
       "recipe ideas", "what's for dinner", "what's for lunch"
   ]
   ```
3. Add detection in `detectQueryType()` — check meal planning indicators **before** general/search indicators (higher priority for explicit meal phrases)
4. Add description: `case .mealPlanning: return "meal-planning"`

**Step 4: Run tests to verify they pass**

Run: `cd SeleneChat && swift test --filter MealPlanningQueryTests`
Expected: All 7 tests PASS

**Step 5: Verify existing tests still pass**

Run: `cd SeleneChat && swift test --filter QueryAnalyzerTests`
Expected: All existing tests PASS (no regressions)

**Step 6: Commit**

```bash
git add SeleneChat/Sources/Services/QueryAnalyzer.swift SeleneChat/Tests/SeleneChatTests/Services/MealPlanningQueryTests.swift
git commit -m "feat(query): add mealPlanning query type detection to QueryAnalyzer"
```

---

### Task 10: MealPlanContextBuilder

**Files:**
- Create: `SeleneChat/Sources/Services/MealPlanContextBuilder.swift`
- Create: `SeleneChat/Tests/SeleneChatTests/Services/MealPlanContextBuilderTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Services/MealPlanContextBuilderTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class MealPlanContextBuilderTests: XCTestCase {

    func testBuildsRecipeLibraryContext() {
        let builder = MealPlanContextBuilder()
        let recipes = [
            Recipe.mock(id: 1, title: "Pasta Carbonara", cuisine: "Italian", protein: "pork"),
            Recipe.mock(id: 2, title: "Chicken Stir Fry", cuisine: "Asian", protein: "chicken"),
        ]
        let context = builder.buildRecipeLibraryContext(recipes: recipes)

        XCTAssertTrue(context.contains("Pasta Carbonara"))
        XCTAssertTrue(context.contains("Chicken Stir Fry"))
        XCTAssertTrue(context.contains("Italian"))
    }

    func testBuildsRecentMealsContext() {
        let builder = MealPlanContextBuilder()
        let recentMeals: [(week: String, items: [(day: String, meal: String, recipeTitle: String)])] = [
            (week: "2026-W06", items: [
                (day: "monday", meal: "dinner", recipeTitle: "Pasta Carbonara"),
                (day: "tuesday", meal: "lunch", recipeTitle: "Chicken Stir Fry"),
            ])
        ]
        let context = builder.buildRecentMealsContext(recentMeals: recentMeals)

        XCTAssertTrue(context.contains("Pasta Carbonara"))
        XCTAssertTrue(context.contains("2026-W06"))
    }

    func testRespectsTokenBudget() {
        let builder = MealPlanContextBuilder()
        // Generate 100 recipes to exceed token budget
        let recipes = (1...100).map { i in
            Recipe.mock(id: Int64(i), title: "Recipe Number \(i) With A Very Long Name That Takes Up Tokens")
        }
        let context = builder.buildRecipeLibraryContext(recipes: recipes)

        // Should be truncated (2500 token budget = ~10000 chars)
        XCTAssertTrue(context.count < 12000)
    }

    func testBuildFullContextCombinesAll() {
        let builder = MealPlanContextBuilder()
        let recipes = [Recipe.mock()]
        let recentMeals: [(week: String, items: [(day: String, meal: String, recipeTitle: String)])] = []

        let context = builder.buildFullContext(
            recipes: recipes,
            recentMeals: recentMeals,
            nutritionTargets: (calories: 2000, protein: 150, carbs: 250, fat: 65)
        )

        XCTAssertTrue(context.contains("Recipe Library"))
        XCTAssertTrue(context.contains("Nutrition Targets"))
        XCTAssertTrue(context.contains("2000"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter MealPlanContextBuilderTests 2>&1 | head -20`
Expected: FAIL — type not found

**Step 3: Write MealPlanContextBuilder**

Create `SeleneChat/Sources/Services/MealPlanContextBuilder.swift`:

```swift
import Foundation

class MealPlanContextBuilder {

    private let tokenBudget = 2500

    private func estimateTokens(_ text: String) -> Int {
        text.count / 4
    }

    func buildRecipeLibraryContext(recipes: [Recipe]) -> String {
        var context = "## Recipe Library (\(recipes.count) recipes)\n\n"
        var currentTokens = estimateTokens(context)

        for recipe in recipes {
            let line = "- \(recipe.compactDescription)\n"
            let lineTokens = estimateTokens(line)
            if currentTokens + lineTokens > tokenBudget {
                context += "\n[... \(recipes.count - recipes.firstIndex(where: { $0.id == recipe.id })! ) more recipes truncated]\n"
                break
            }
            context += line
            currentTokens += lineTokens
        }

        return context
    }

    func buildRecentMealsContext(recentMeals: [(week: String, items: [(day: String, meal: String, recipeTitle: String)])]) -> String {
        guard !recentMeals.isEmpty else { return "" }

        var context = "## Recent Meals (avoid repetition)\n\n"
        for plan in recentMeals {
            context += "### \(plan.week)\n"
            for item in plan.items {
                context += "- \(item.day) \(item.meal): \(item.recipeTitle)\n"
            }
            context += "\n"
        }
        return context
    }

    func buildFullContext(
        recipes: [Recipe],
        recentMeals: [(week: String, items: [(day: String, meal: String, recipeTitle: String)])],
        nutritionTargets: (calories: Int, protein: Int, carbs: Int, fat: Int)?
    ) -> String {
        var context = ""

        context += buildRecipeLibraryContext(recipes: recipes)
        context += "\n"
        context += buildRecentMealsContext(recentMeals: recentMeals)

        if let targets = nutritionTargets {
            context += "## Nutrition Targets (daily)\n"
            context += "- Calories: \(targets.calories)\n"
            context += "- Protein: \(targets.protein)g\n"
            context += "- Carbs: \(targets.carbs)g\n"
            context += "- Fat: \(targets.fat)g\n\n"
        }

        return context
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd SeleneChat && swift test --filter MealPlanContextBuilderTests`
Expected: All 4 tests PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/MealPlanContextBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/MealPlanContextBuilderTests.swift
git commit -m "feat: add MealPlanContextBuilder with recipe library and recent meals context"
```

---

### Task 11: MealPlanPromptBuilder

**Files:**
- Create: `SeleneChat/Sources/Services/MealPlanPromptBuilder.swift`
- Create: `SeleneChat/Tests/SeleneChatTests/Services/MealPlanPromptBuilderTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Services/MealPlanPromptBuilderTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class MealPlanPromptBuilderTests: XCTestCase {

    func testBuildSystemPromptContainsActionMarkers() {
        let builder = MealPlanPromptBuilder()
        let prompt = builder.buildSystemPrompt()

        XCTAssertTrue(prompt.contains("[MEAL:"))
        XCTAssertTrue(prompt.contains("[SHOP:"))
        XCTAssertTrue(prompt.contains("ADHD"))
    }

    func testBuildPlanningPromptIncludesContext() {
        let builder = MealPlanPromptBuilder()
        let context = "## Recipe Library\n- Pasta | Italian | 30 min\n"
        let prompt = builder.buildPlanningPrompt(
            query: "plan next week's meals",
            context: context,
            conversationHistory: []
        )

        XCTAssertTrue(prompt.contains("plan next week"))
        XCTAssertTrue(prompt.contains("Recipe Library"))
    }

    func testBuildPlanningPromptIncludesHistory() {
        let builder = MealPlanPromptBuilder()
        let history = [
            (role: "user", content: "plan next week"),
            (role: "assistant", content: "Here are my suggestions...")
        ]
        let prompt = builder.buildPlanningPrompt(
            query: "swap tuesday dinner",
            context: "",
            conversationHistory: history
        )

        XCTAssertTrue(prompt.contains("swap tuesday dinner"))
        XCTAssertTrue(prompt.contains("plan next week"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter MealPlanPromptBuilderTests 2>&1 | head -20`
Expected: FAIL — type not found

**Step 3: Write MealPlanPromptBuilder**

Create `SeleneChat/Sources/Services/MealPlanPromptBuilder.swift`:

```swift
import Foundation

class MealPlanPromptBuilder {

    func buildSystemPrompt() -> String {
        """
        You are a meal planning assistant for someone with ADHD. Your job is to suggest \
        concrete meals from their recipe library — not generic ideas.

        Guidelines:
        - Suggest recipes the user already has. Reference them by exact title.
        - Keep plans realistic: max 2 complex meals per week, rest should be quick/easy.
        - Consider variety: don't repeat proteins or cuisines on consecutive days.
        - Factor in leftovers: suggest cooking extra on Sunday for Monday lunch, etc.
        - If the user has nutrition targets, try to roughly align suggestions.

        When suggesting a full meal plan, use these markers (one per meal slot):
        [MEAL: day | meal | Recipe Title | recipe_id: N]

        Example:
        [MEAL: monday | dinner | Pasta Carbonara | recipe_id: 42]
        [MEAL: tuesday | lunch | leftover Pasta Carbonara | recipe_id: 42]

        When the user confirms the plan, also suggest shopping items:
        [SHOP: ingredient | amount | unit | category]

        Categories: produce, dairy, meat, pantry, frozen, bakery, other

        Example:
        [SHOP: spaghetti | 400 | g | pantry]
        [SHOP: guanciale | 200 | g | meat]

        Only include [MEAL:] and [SHOP:] markers when making concrete suggestions. \
        During discussion, just talk normally.
        """
    }

    func buildPlanningPrompt(
        query: String,
        context: String,
        conversationHistory: [(role: String, content: String)]
    ) -> String {
        var prompt = ""

        if !context.isEmpty {
            prompt += context + "\n\n"
        }

        if !conversationHistory.isEmpty {
            prompt += "## Conversation So Far\n\n"
            for turn in conversationHistory.suffix(6) {
                let label = turn.role == "user" ? "User" : "Assistant"
                prompt += "**\(label):** \(turn.content)\n\n"
            }
        }

        prompt += "**User:** \(query)"

        return prompt
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd SeleneChat && swift test --filter MealPlanPromptBuilderTests`
Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/MealPlanPromptBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/MealPlanPromptBuilderTests.swift
git commit -m "feat: add MealPlanPromptBuilder with ADHD-aware system prompt and action markers"
```

---

### Task 12: ActionExtractor — MEAL and SHOP Markers

**Files:**
- Modify: `SeleneChat/Sources/Services/ActionExtractor.swift`
- Create: `SeleneChat/Tests/SeleneChatTests/Services/MealActionExtractorTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Services/MealActionExtractorTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class MealActionExtractorTests: XCTestCase {

    func testExtractsMealMarker() {
        let extractor = ActionExtractor()
        let response = """
        Here's my suggestion for Monday dinner:
        [MEAL: monday | dinner | Pasta Carbonara | recipe_id: 42]
        """
        let meals = extractor.extractMealActions(from: response)

        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals[0].day, "monday")
        XCTAssertEqual(meals[0].meal, "dinner")
        XCTAssertEqual(meals[0].recipeTitle, "Pasta Carbonara")
        XCTAssertEqual(meals[0].recipeId, 42)
    }

    func testExtractsMultipleMealMarkers() {
        let extractor = ActionExtractor()
        let response = """
        [MEAL: monday | dinner | Pasta Carbonara | recipe_id: 42]
        [MEAL: tuesday | lunch | Chicken Stir Fry | recipe_id: 15]
        [MEAL: wednesday | dinner | Sheet Pan Salmon | recipe_id: 8]
        """
        let meals = extractor.extractMealActions(from: response)
        XCTAssertEqual(meals.count, 3)
    }

    func testExtractsShopMarker() {
        let extractor = ActionExtractor()
        let response = """
        [SHOP: spaghetti | 400 | g | pantry]
        [SHOP: guanciale | 200 | g | meat]
        """
        let items = extractor.extractShopActions(from: response)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].ingredient, "spaghetti")
        XCTAssertEqual(items[0].amount, 400)
        XCTAssertEqual(items[0].unit, "g")
        XCTAssertEqual(items[0].category, "pantry")
    }

    func testRemovesMealAndShopMarkers() {
        let extractor = ActionExtractor()
        let response = """
        Here's Monday dinner:
        [MEAL: monday | dinner | Pasta | recipe_id: 1]
        And you'll need:
        [SHOP: pasta | 400 | g | pantry]
        Enjoy!
        """
        let cleaned = extractor.removeMealAndShopMarkers(from: response)

        XCTAssertFalse(cleaned.contains("[MEAL:"))
        XCTAssertFalse(cleaned.contains("[SHOP:"))
        XCTAssertTrue(cleaned.contains("Monday dinner"))
        XCTAssertTrue(cleaned.contains("Enjoy!"))
    }

    func testHandlesMealMarkerWithoutRecipeId() {
        let extractor = ActionExtractor()
        let response = "[MEAL: monday | dinner | Homemade something | recipe_id: 0]"
        let meals = extractor.extractMealActions(from: response)

        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals[0].recipeTitle, "Homemade something")
        XCTAssertNil(meals[0].recipeId)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter MealActionExtractorTests 2>&1 | head -20`
Expected: FAIL — `extractMealActions` not found

**Step 3: Add meal/shop extraction to ActionExtractor**

Add to `ActionExtractor.swift`:

```swift
struct ExtractedMealAction {
    let day: String
    let meal: String
    let recipeTitle: String
    let recipeId: Int64?
}

struct ExtractedShopAction {
    let ingredient: String
    let amount: Double?
    let unit: String?
    let category: String?
}

private let mealPattern = #"\[MEAL:\s*(\w+)\s*\|\s*(\w+)\s*\|\s*([^|]+?)\s*\|\s*recipe_id:\s*(\d+)\s*\]"#

private let shopPattern = #"\[SHOP:\s*([^|]+?)\s*\|\s*([\d.]+)\s*\|\s*([^|]+?)\s*\|\s*(\w+)\s*\]"#

func extractMealActions(from response: String) -> [ExtractedMealAction] {
    // Regex match mealPattern, map to ExtractedMealAction
    // recipe_id: 0 → nil
}

func extractShopActions(from response: String) -> [ExtractedShopAction] {
    // Regex match shopPattern, map to ExtractedShopAction
}

func removeMealAndShopMarkers(from response: String) -> String {
    // Remove [MEAL: ...] and [SHOP: ...] lines, trim extra blank lines
}
```

**Step 4: Run tests to verify they pass**

Run: `cd SeleneChat && swift test --filter MealActionExtractorTests`
Expected: All 5 tests PASS

**Step 5: Verify existing ActionExtractor tests still pass**

Run: `cd SeleneChat && swift test --filter ActionExtractorTests`
Expected: All existing tests PASS

**Step 6: Commit**

```bash
git add SeleneChat/Sources/Services/ActionExtractor.swift SeleneChat/Tests/SeleneChatTests/Services/MealActionExtractorTests.swift
git commit -m "feat(actions): add MEAL and SHOP marker extraction to ActionExtractor"
```

---

### Task 13: ChatViewModel — Meal Planning Route

**Files:**
- Modify: `SeleneChat/Sources/ViewModels/ChatViewModel.swift`
- Create: `SeleneChat/Tests/SeleneChatTests/Integration/MealPlanningIntegrationTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Integration/MealPlanningIntegrationTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class MealPlanningIntegrationTests: XCTestCase {

    func testMealPlanContextBuilderIntegration() {
        // Verify context builder + prompt builder work together
        let contextBuilder = MealPlanContextBuilder()
        let promptBuilder = MealPlanPromptBuilder()

        let recipes = [
            Recipe.mock(id: 1, title: "Pasta Carbonara", cuisine: "Italian"),
            Recipe.mock(id: 2, title: "Chicken Stir Fry", cuisine: "Asian"),
        ]

        let context = contextBuilder.buildFullContext(
            recipes: recipes,
            recentMeals: [],
            nutritionTargets: (calories: 2000, protein: 150, carbs: 250, fat: 65)
        )

        let prompt = promptBuilder.buildPlanningPrompt(
            query: "plan next week",
            context: context,
            conversationHistory: []
        )

        XCTAssertTrue(prompt.contains("Pasta Carbonara"))
        XCTAssertTrue(prompt.contains("Chicken Stir Fry"))
        XCTAssertTrue(prompt.contains("2000"))
        XCTAssertTrue(prompt.contains("plan next week"))
    }

    func testMealActionExtractionFromFullResponse() {
        let extractor = ActionExtractor()
        let response = """
        Here's your meal plan for next week:

        **Monday:**
        [MEAL: monday | breakfast | Overnight Oats | recipe_id: 5]
        [MEAL: monday | lunch | Chicken Stir Fry | recipe_id: 2]
        [MEAL: monday | dinner | Pasta Carbonara | recipe_id: 1]

        **Shopping list:**
        [SHOP: spaghetti | 400 | g | pantry]
        [SHOP: eggs | 4 | count | dairy]
        [SHOP: chicken breast | 500 | g | meat]

        This plan keeps Monday light with quick meals and saves the heavier cooking for when you have energy.
        """

        let meals = extractor.extractMealActions(from: response)
        XCTAssertEqual(meals.count, 3)
        XCTAssertEqual(meals[0].day, "monday")
        XCTAssertEqual(meals[0].meal, "breakfast")

        let items = extractor.extractShopActions(from: response)
        XCTAssertEqual(items.count, 3)

        let cleaned = extractor.removeMealAndShopMarkers(from: response)
        XCTAssertFalse(cleaned.contains("[MEAL:"))
        XCTAssertTrue(cleaned.contains("Monday"))
        XCTAssertTrue(cleaned.contains("energy"))
    }
}
```

**Step 2: Run tests to verify they pass**

These tests use already-built components, so they should pass:
Run: `cd SeleneChat && swift test --filter MealPlanningIntegrationTests`
Expected: All 2 tests PASS

**Step 3: Add meal planning handler to ChatViewModel**

Read `ChatViewModel.swift` first to find the exact insertion point in `sendMessage()`.

Add after the deep-dive/synthesis detection block but before general query handling:

```swift
// Check for meal planning queries
if queryAnalyzer.detectQueryType(content) == .mealPlanning {
    let (response, actions) = try await handleMealPlanningQuery(query: content)
    // ... create message, handle actions, save session
    return
}
```

Add the handler method:

```swift
// MARK: - Meal Planning

private let mealPlanContextBuilder = MealPlanContextBuilder()
private let mealPlanPromptBuilder = MealPlanPromptBuilder()

private func handleMealPlanningQuery(query: String) async throws -> (String, [ActionExtractor.ExtractedMealAction]) {
    // 1. Fetch recipes from DB
    let recipes = try await databaseService.getAllRecipes()

    // 2. Fetch recent meal plans
    let recentMeals = try await databaseService.getRecentMealPlans(weeks: 3)

    // 3. Build context
    let context = mealPlanContextBuilder.buildFullContext(
        recipes: recipes,
        recentMeals: recentMeals,
        nutritionTargets: nil  // TODO: load from KitchenOS vault
    )

    // 4. Build conversation history from current session
    let history = currentSession.messages.suffix(6).map { msg in
        (role: msg.role == .user ? "user" : "assistant", content: msg.content)
    }

    // 5. Build prompt
    let systemPrompt = mealPlanPromptBuilder.buildSystemPrompt()
    let userPrompt = mealPlanPromptBuilder.buildPlanningPrompt(
        query: query,
        context: context,
        conversationHistory: history
    )

    // 6. Send to Ollama
    let response = try await ollamaService.generate(
        system: systemPrompt,
        prompt: userPrompt
    )

    // 7. Extract meal actions
    let mealActions = actionExtractor.extractMealActions(from: response)
    let shopActions = actionExtractor.extractShopActions(from: response)

    // 8. Store pending actions if any
    if !mealActions.isEmpty || !shopActions.isEmpty {
        pendingMealActions = mealActions
        pendingShopActions = shopActions
    }

    // 9. Clean response for display
    let cleanResponse = actionExtractor.removeMealAndShopMarkers(from: response)

    return (cleanResponse, mealActions)
}
```

Add pending action state:
```swift
@Published var pendingMealActions: [ActionExtractor.ExtractedMealAction] = []
@Published var pendingShopActions: [ActionExtractor.ExtractedShopAction] = []
```

Add confirmation method:
```swift
func confirmMealPlan(week: String) async throws {
    // 1. Create/update meal_plan row
    // 2. Insert meal_plan_items from pendingMealActions
    // 3. Insert shopping_items from pendingShopActions
    // 4. Clear pending actions
    pendingMealActions = []
    pendingShopActions = []
}
```

**Step 4: Build to verify compilation**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add SeleneChat/Sources/ViewModels/ChatViewModel.swift SeleneChat/Tests/SeleneChatTests/Integration/MealPlanningIntegrationTests.swift
git commit -m "feat: route meal planning queries through specialized handler in ChatViewModel"
```

---

### Task 14: Meal Plan Confirmation — DB Write

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift`
- Create: `SeleneChat/Tests/SeleneChatTests/Services/MealPlanWriteTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Services/MealPlanWriteTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class MealPlanWriteTests: XCTestCase {

    @MainActor
    func testCreateMealPlanReturnsId() async throws {
        let db = DatabaseService.shared
        let id = try await db.createMealPlan(
            week: "test-2099-W01",
            testRun: "test-meal-write"
        )
        XCTAssertGreaterThan(id, 0)

        // Cleanup
        try await db.deleteMealPlan(id: id)
    }

    @MainActor
    func testInsertMealPlanItem() async throws {
        let db = DatabaseService.shared
        let planId = try await db.createMealPlan(
            week: "test-2099-W02",
            testRun: "test-meal-write"
        )

        try await db.insertMealPlanItem(
            planId: planId,
            day: "monday",
            meal: "dinner",
            recipeId: nil,
            recipeTitle: "Test Recipe"
        )

        let items = try await db.getMealPlanForWeek("test-2099-W02")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].recipeTitle, "Test Recipe")

        // Cleanup
        try await db.deleteMealPlan(id: planId)
    }

    @MainActor
    func testInsertShoppingItem() async throws {
        let db = DatabaseService.shared
        let planId = try await db.createMealPlan(
            week: "test-2099-W03",
            testRun: "test-meal-write"
        )

        try await db.insertShoppingItem(
            planId: planId,
            ingredient: "spaghetti",
            amount: 400,
            unit: "g",
            category: "pantry"
        )

        // Cleanup
        try await db.deleteMealPlan(id: planId)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter MealPlanWriteTests 2>&1 | head -20`
Expected: FAIL — methods not found

**Step 3: Add write methods to DatabaseService**

Add to `DatabaseService.swift`:

```swift
// MARK: - Meal Plan Write Operations

func createMealPlan(week: String, testRun: String? = nil) async throws -> Int64 {
    // INSERT INTO meal_plans (week, status, created_at, test_run) VALUES (?, 'draft', ?, ?)
    // Return lastInsertRowid
}

func insertMealPlanItem(planId: Int64, day: String, meal: String, recipeId: Int64?, recipeTitle: String, notes: String? = nil) async throws {
    // INSERT INTO meal_plan_items (meal_plan_id, day, meal, recipe_id, recipe_title, notes) VALUES (?, ?, ?, ?, ?, ?)
}

func insertShoppingItem(planId: Int64, ingredient: String, amount: Double?, unit: String?, category: String?) async throws {
    // INSERT INTO shopping_items (meal_plan_id, ingredient, amount, unit, category, created_at) VALUES (?, ?, ?, ?, ?, ?)
}

func updateMealPlanStatus(id: Int64, status: String) async throws {
    // UPDATE meal_plans SET status = ?, updated_at = ? WHERE id = ?
}

func deleteMealPlan(id: Int64) async throws {
    // DELETE FROM meal_plans WHERE id = ? (cascades to items and shopping)
}
```

**Step 4: Run tests to verify they pass**

Run: `cd SeleneChat && swift test --filter MealPlanWriteTests`
Expected: All 3 tests PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/DatabaseService.swift SeleneChat/Tests/SeleneChatTests/Services/MealPlanWriteTests.swift
git commit -m "feat(db): add meal plan and shopping item write methods to DatabaseService"
```

---

## Phase 3: Obsidian Export + KitchenOS Awareness

### Task 15: Meal Plan Obsidian Export

**Files:**
- Create: `src/lib/meal-plan-exporter.ts`
- Create: `src/lib/meal-plan-exporter.test.ts`

**Step 1: Write the failing test**

Create `src/lib/meal-plan-exporter.test.ts`:

```typescript
import assert from 'assert';
import { generateMealPlanMarkdown, generateShoppingListMarkdown } from './meal-plan-exporter';

async function runTests() {
  console.log('Meal Plan Exporter Tests\n');

  // Test 1: Generates KitchenOS-format meal plan
  console.log('Test 1: Generates KitchenOS-format meal plan markdown');
  {
    const items = [
      { day: 'monday', meal: 'breakfast', recipe_title: 'Overnight Oats' },
      { day: 'monday', meal: 'lunch', recipe_title: 'Chicken Stir Fry' },
      { day: 'monday', meal: 'dinner', recipe_title: 'Pasta Carbonara' },
      { day: 'tuesday', meal: 'dinner', recipe_title: 'Sheet Pan Salmon' },
    ];

    const md = generateMealPlanMarkdown('2026-W08', items);

    // Must have KitchenOS format headers
    assert.ok(md.includes('# Meal Plan - Week 08'), 'Should have week header');
    assert.ok(md.includes('## Monday'), 'Should have Monday header');
    assert.ok(md.includes('### Breakfast'), 'Should have meal headers');
    assert.ok(md.includes('[[Overnight Oats]]'), 'Should use wiki links');
    assert.ok(md.includes('[[Pasta Carbonara]]'), 'Should use wiki links');
    assert.ok(md.includes('## Tuesday'), 'Should have Tuesday');
    assert.ok(md.includes('[[Sheet Pan Salmon]]'), 'Should have Tuesday dinner');
    console.log('  PASS');
  }

  // Test 2: Generates shopping list markdown
  console.log('Test 2: Generates shopping list markdown');
  {
    const items = [
      { ingredient: 'spaghetti', amount: 400, unit: 'g', category: 'pantry' },
      { ingredient: 'chicken breast', amount: 500, unit: 'g', category: 'meat' },
      { ingredient: 'broccoli', amount: 1, unit: 'head', category: 'produce' },
    ];

    const md = generateShoppingListMarkdown('2026-W08', items);

    assert.ok(md.includes('# Shopping List'), 'Should have header');
    assert.ok(md.includes('## Produce'), 'Should group by category');
    assert.ok(md.includes('- [ ] 1 head broccoli'), 'Should have checkbox format');
    assert.ok(md.includes('## Meat'), 'Should have meat category');
    assert.ok(md.includes('## Pantry'), 'Should have pantry category');
    console.log('  PASS');
  }

  console.log('\nAll meal plan exporter tests passed!');
}

runTests().catch(err => {
  console.error('\nTest failed:', err.message);
  process.exit(1);
});
```

**Step 2: Run test to verify it fails**

Run: `npx ts-node src/lib/meal-plan-exporter.test.ts`
Expected: FAIL — module not found

**Step 3: Write the exporter**

Create `src/lib/meal-plan-exporter.ts`:

The module exports:
- `generateMealPlanMarkdown(week: string, items: MealPlanItem[]): string` — generates KitchenOS-format meal plan with wiki links
- `generateShoppingListMarkdown(week: string, items: ShoppingItem[]): string` — generates checkbox shopping list grouped by category
- `exportMealPlanToVault(week: string, vaultPath: string): void` — reads from DB, writes both files to vault

Meal plan format must match KitchenOS's `meal_plan_parser.py` expectations:
```markdown
# Meal Plan - Week NN (Mon Date - Sun Date)

## Monday (YYYY-MM-DD)
### Breakfast
[[Recipe Name]]

### Lunch
[[Recipe Name]]

### Dinner
[[Recipe Name]]

### Notes

```

Shopping list format:
```markdown
# Shopping List - Week NN

## Produce
- [ ] 1 head broccoli
- [ ] 2 cups spinach

## Dairy
- [ ] 6 count eggs

## Meat
- [ ] 500 g chicken breast

## Pantry
- [ ] 400 g spaghetti
```

**Step 4: Run tests to verify they pass**

Run: `npx ts-node src/lib/meal-plan-exporter.test.ts`
Expected: All 2 tests PASS

**Step 5: Commit**

```bash
git add src/lib/meal-plan-exporter.ts src/lib/meal-plan-exporter.test.ts
git commit -m "feat: add meal plan and shopping list Obsidian exporter in KitchenOS format"
```

---

### Task 16: Export Trigger in SeleneChat

**Files:**
- Modify: `SeleneChat/Sources/ViewModels/ChatViewModel.swift`

**Step 1: Add export call after meal plan confirmation**

In `confirmMealPlan()`, after writing to DB, trigger the Obsidian export:

```swift
func confirmMealPlan(week: String) async throws {
    // ... existing DB writes from Task 14 ...

    // Trigger Obsidian export via workflow
    let runner = WorkflowRunner()
    let result = try await runner.runWorkflow(
        scriptPath: "src/lib/meal-plan-exporter.ts",
        arguments: [week]
    )

    // Update meal plan status
    try await databaseService.updateMealPlanStatus(id: planId, status: "active")
    try await databaseService.updateMealPlanExportedAt(id: planId)

    pendingMealActions = []
    pendingShopActions = []
}
```

Alternatively, if the export should happen TypeScript-side, add a simple endpoint or CLI argument to `meal-plan-exporter.ts` that reads from DB and writes to vault. The SeleneChat side just calls `npx ts-node src/lib/meal-plan-exporter.ts --week 2026-W08`.

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/ViewModels/ChatViewModel.swift
git commit -m "feat: trigger Obsidian export on meal plan confirmation"
```

---

### Task 17: Status File in KitchenOS Vault

**Files:**
- Modify: `src/workflows/index-recipes.ts`

**Step 1: Add status file generation to index-recipes workflow**

After indexing completes, write a status file to the KitchenOS vault:

```typescript
function writeStatusFile(vaultPath: string, stats: { recipeCount: number; lastIndexed: string; activePlan: string | null }) {
  const statusPath = join(vaultPath, 'Selene Integration', 'Status.md');
  const dir = join(vaultPath, 'Selene Integration');
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  const content = `---
last_indexed: ${stats.lastIndexed}
recipe_count: ${stats.recipeCount}
active_plan: ${stats.activePlan || 'none'}
---

# Selene Integration Status

| Metric | Value |
|--------|-------|
| Recipes Indexed | ${stats.recipeCount} |
| Last Indexed | ${stats.lastIndexed} |
| Active Meal Plan | ${stats.activePlan || 'None'} |

> This file is auto-generated by Selene. Open SeleneChat to plan meals.
`;

  writeFileSync(statusPath, content, 'utf-8');
}
```

Call at end of `indexRecipes()`.

**Step 2: Run workflow to verify**

Run: `npx ts-node src/workflows/index-recipes.ts`
Expected: Status file appears in KitchenOS vault at `Selene Integration/Status.md`

**Step 3: Commit**

```bash
git add src/workflows/index-recipes.ts
git commit -m "feat: write Selene integration status file to KitchenOS vault"
```

---

### Task 18: End-to-End Integration Test

**Files:**
- Create: `src/workflows/index-recipes.integration-test.ts`

**Step 1: Write integration test**

Tests the full loop:
1. Create test recipe files in a temp vault directory
2. Run `indexRecipes()` against the temp vault
3. Verify recipes appear in DB with `test_run` marker
4. Verify meal plan items indexed
5. Call `exportMealPlanToVault()` with test data
6. Verify output files match KitchenOS format
7. Cleanup test data

```typescript
// Run with: SELENE_ENV=test npx ts-node src/workflows/index-recipes.integration-test.ts
```

**Step 2: Run integration test**

Run: `SELENE_ENV=test npx ts-node src/workflows/index-recipes.integration-test.ts`
Expected: All assertions pass, test data cleaned up

**Step 3: Commit**

```bash
git add src/workflows/index-recipes.integration-test.ts
git commit -m "test: add end-to-end integration test for KitchenOS recipe indexing and export"
```

---

### Task 19: Run Full SeleneChat Test Suite

**Files:** None (verification only)

**Step 1: Run all SeleneChat tests**

Run: `cd SeleneChat && swift test`
Expected: All tests PASS (270+ existing + ~30 new)

**Step 2: Run all TypeScript tests**

Run: `npx ts-node src/lib/recipe-parser.test.ts && npx ts-node src/workflows/index-recipes.test.ts && npx ts-node src/lib/meal-plan-exporter.test.ts`
Expected: All tests PASS

**Step 3: Build and deploy SeleneChat**

Run: `cd SeleneChat && ./build-app.sh && cp -R .build/release/SeleneChat.app /Applications/`
Expected: App builds and installs

**Step 4: Manual smoke test**

1. Open SeleneChat
2. Type "help me plan next week's meals"
3. Verify it suggests recipes from your library
4. Verify `index-recipes` appears in WorkflowScheduler status

---

### Task 20: Final Commit and Documentation

**Files:**
- Modify: `docs/plans/INDEX.md` (move design to "In Progress" or "Done")
- Modify: `.claude/PROJECT-STATUS.md` (update with new feature)

**Step 1: Update design doc status**

Move the KitchenOS integration entry from "Ready" to "Done" in `docs/plans/INDEX.md`.

**Step 2: Update PROJECT-STATUS.md**

Add to recent completions and update the system architecture diagram.

**Step 3: Commit**

```bash
git add docs/plans/INDEX.md .claude/PROJECT-STATUS.md
git commit -m "docs: mark KitchenOS-Selene integration as complete"
```
