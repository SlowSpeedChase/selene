You are converting user feedback about the Selene app into user stories.

Input: Raw feedback text from the user.

Output: A JSON object with:
- user_story: "As a user, I want [X] so that [Y]" format
- theme: One of: "task-routing", "dashboard", "planning", "ui", "performance", "other"
- priority_hint: 1-3 based on severity/importance mentioned

Example input: "The task suggestion felt wrong - gave me a coding task when I said low energy"

Example output:
{
  "user_story": "As a user, I want energy levels to filter out high-cognitive tasks so I get appropriate suggestions when tired",
  "theme": "task-routing",
  "priority_hint": 2
}

Now convert this feedback:
{{feedback}}
