"""
Built-in prompt templates for common analysis tasks.
"""

from typing import Dict, List

from .models import PromptTemplate, PromptCategory, TemplateVariable


def get_builtin_templates() -> List[PromptTemplate]:
    """Get all built-in prompt templates."""
    
    templates = []
    
    # SUMMARIZATION TEMPLATES
    templates.extend([
        PromptTemplate(
            name="Basic Summary",
            description="Create a concise summary of the content",
            category=PromptCategory.SUMMARIZATION,
            template="""Please create a concise summary of the following content:

{content}

Summary Requirements:
- Keep it brief and focused on key points
- Use clear, professional language
- Highlight the most important information
- Maximum {max_length} words

Summary:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to summarize",
                    required=True
                ),
                TemplateVariable(
                    name="max_length",
                    description="Maximum number of words for summary",
                    required=False,
                    default_value="100"
                )
            ],
            tags=["summary", "basic", "general"],
            author="Selene System",
            model_optimizations={
                "llama3.2": {"temperature": 0.3, "max_tokens": 200},
                "mistral": {"temperature": 0.2, "max_tokens": 250},
                "gpt-4": {"temperature": 0.3, "max_tokens": 200}
            }
        ),
        
        PromptTemplate(
            name="Executive Summary",
            description="Create an executive-level summary with key insights",
            category=PromptCategory.SUMMARIZATION,
            template="""Please create an executive summary of the following content:

{content}

Executive Summary Requirements:
- Focus on strategic insights and key takeaways
- Include actionable recommendations if applicable
- Use executive-level language
- Structure: Key Points, Insights, Recommendations
- Target audience: {audience}

Executive Summary:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to summarize",
                    required=True
                ),
                TemplateVariable(
                    name="audience",
                    description="Target audience for the summary",
                    required=False,
                    default_value="business executives"
                )
            ],
            tags=["summary", "executive", "business", "insights"],
            author="Selene System"
        )
    ])
    
    # ENHANCEMENT TEMPLATES
    templates.extend([
        PromptTemplate(
            name="Content Enhancement",
            description="Improve clarity, structure, and readability of content",
            category=PromptCategory.ENHANCEMENT,
            template="""Please enhance the following content by improving its clarity, structure, and readability:

Original Content:
{content}

Enhancement Requirements:
- Improve clarity and flow
- Fix grammar and style issues
- Maintain the original meaning and tone
- {enhancement_focus}
- Keep the enhanced version at similar length

Enhanced Content:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to enhance",
                    required=True
                ),
                TemplateVariable(
                    name="enhancement_focus",
                    description="Specific area to focus enhancement on",
                    required=False,
                    default_value="Ensure professional tone and clear structure"
                )
            ],
            tags=["enhancement", "clarity", "writing", "improvement"],
            author="Selene System"
        ),
        
        PromptTemplate(
            name="Academic Enhancement",
            description="Enhance content for academic or technical contexts",
            category=PromptCategory.ENHANCEMENT,
            template="""Please enhance the following content for academic/technical presentation:

Original Content:
{content}

Academic Enhancement Requirements:
- Use formal, academic language
- Improve logical structure and argumentation
- Add technical precision where appropriate
- Ensure citations and references are properly formatted
- Target discipline: {discipline}

Enhanced Academic Content:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to enhance academically",
                    required=True
                ),
                TemplateVariable(
                    name="discipline",
                    description="Academic discipline or field",
                    required=False,
                    default_value="general academic"
                )
            ],
            tags=["enhancement", "academic", "technical", "formal"],
            author="Selene System"
        )
    ])
    
    # ANALYSIS TEMPLATES
    templates.extend([
        PromptTemplate(
            name="Insight Extraction",
            description="Extract key insights and patterns from content",
            category=PromptCategory.ANALYSIS,
            template="""Please analyze the following content and extract key insights:

Content to Analyze:
{content}

Analysis Requirements:
- Identify main themes and patterns
- Extract actionable insights
- Highlight important trends or connections
- Focus on: {analysis_focus}
- Provide supporting evidence for each insight

Key Insights:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to analyze for insights",
                    required=True
                ),
                TemplateVariable(
                    name="analysis_focus",
                    description="Specific aspect to focus the analysis on",
                    required=False,
                    default_value="strategic implications and actionable opportunities"
                )
            ],
            tags=["analysis", "insights", "patterns", "trends"],
            author="Selene System"
        ),
        
        PromptTemplate(
            name="Question Generation",
            description="Generate thought-provoking questions based on content",
            category=PromptCategory.ANALYSIS,
            template="""Based on the following content, generate thoughtful questions that encourage deeper thinking:

Content:
{content}

Question Generation Requirements:
- Create {num_questions} questions
- Mix of analytical, critical thinking, and exploratory questions
- Questions should be {question_type}
- Encourage deeper understanding and reflection
- Focus area: {focus_area}

Generated Questions:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to generate questions from",
                    required=True
                ),
                TemplateVariable(
                    name="num_questions",
                    description="Number of questions to generate",
                    required=False,
                    default_value="5-7"
                ),
                TemplateVariable(
                    name="question_type",
                    description="Type of questions to focus on",
                    required=False,
                    default_value="open-ended and thought-provoking"
                ),
                TemplateVariable(
                    name="focus_area",
                    description="Specific area to focus questions on",
                    required=False,
                    default_value="practical applications and implications"
                )
            ],
            tags=["analysis", "questions", "critical thinking", "exploration"],
            author="Selene System"
        )
    ])
    
    # CLASSIFICATION TEMPLATES
    templates.extend([
        PromptTemplate(
            name="Content Classification",
            description="Classify content into categories with reasoning",
            category=PromptCategory.CLASSIFICATION,
            template="""Please classify the following content into appropriate categories:

Content to Classify:
{content}

Classification Requirements:
- Available categories: {categories}
- Provide the most relevant category
- Include confidence level (1-10)
- Explain your reasoning
- Consider: {classification_criteria}

Classification Result:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to classify",
                    required=True
                ),
                TemplateVariable(
                    name="categories",
                    description="Available categories for classification",
                    required=False,
                    default_value="Research, Analysis, Documentation, Communication, Planning, Meeting Notes"
                ),
                TemplateVariable(
                    name="classification_criteria",
                    description="Specific criteria to consider during classification",
                    required=False,
                    default_value="content type, purpose, audience, and format"
                )
            ],
            tags=["classification", "categorization", "organization"],
            author="Selene System"
        ),
        
        PromptTemplate(
            name="Priority Classification",
            description="Classify content by priority and urgency",
            category=PromptCategory.CLASSIFICATION,
            template="""Please classify the following content by priority and urgency:

Content:
{content}

Priority Classification Requirements:
- Priority levels: {priority_levels}
- Urgency levels: {urgency_levels}
- Consider impact, time sensitivity, and importance
- Provide specific reasoning for each classification
- Suggest recommended timeline for action

Priority Assessment:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to classify by priority",
                    required=True
                ),
                TemplateVariable(
                    name="priority_levels",
                    description="Available priority levels",
                    required=False,
                    default_value="High, Medium, Low"
                ),
                TemplateVariable(
                    name="urgency_levels",
                    description="Available urgency levels",
                    required=False,
                    default_value="Urgent, Moderate, Can Wait"
                )
            ],
            tags=["classification", "priority", "urgency", "planning"],
            author="Selene System"
        )
    ])
    
    # EXTRACTION TEMPLATES
    templates.extend([
        PromptTemplate(
            name="Key Information Extraction",
            description="Extract specific types of information from content",
            category=PromptCategory.EXTRACTION,
            template="""Please extract the following information from the content:

Content:
{content}

Information to Extract:
{extraction_targets}

Extraction Requirements:
- Be precise and accurate
- Provide source context where possible
- Indicate confidence level for each extraction
- Format as structured data
- Include any relevant metadata

Extracted Information:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to extract information from",
                    required=True
                ),
                TemplateVariable(
                    name="extraction_targets",
                    description="Specific types of information to extract",
                    required=False,
                    default_value="key facts, dates, names, decisions, action items, and important numbers"
                )
            ],
            tags=["extraction", "information", "structured data"],
            author="Selene System"
        ),
        
        PromptTemplate(
            name="Action Item Extraction",
            description="Extract actionable items and tasks from content",
            category=PromptCategory.EXTRACTION,
            template="""Please extract all action items and tasks from the following content:

Content:
{content}

Action Item Extraction Requirements:
- Identify specific, actionable tasks
- Include responsible parties if mentioned
- Extract deadlines and timelines
- Note priority or urgency indicators
- Format as: [Action] - [Owner] - [Deadline] - [Priority]
- Focus on: {focus_type}

Action Items:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to extract action items from",
                    required=True
                ),
                TemplateVariable(
                    name="focus_type",
                    description="Type of actions to focus on",
                    required=False,
                    default_value="immediate next steps and concrete deliverables"
                )
            ],
            tags=["extraction", "action items", "tasks", "project management"],
            author="Selene System"
        )
    ])
    
    # GENERATION TEMPLATES
    templates.extend([
        PromptTemplate(
            name="Creative Expansion",
            description="Expand content with creative additions and perspectives",
            category=PromptCategory.GENERATION,
            template="""Please creatively expand on the following content:

Original Content:
{content}

Creative Expansion Requirements:
- Add {expansion_type} perspectives
- Maintain consistency with original tone
- Include creative examples or analogies
- Expand length by approximately {expansion_factor}
- Focus on: {creative_focus}

Expanded Content:""",
            variables=[
                TemplateVariable(
                    name="content",
                    description="The content to expand creatively",
                    required=True
                ),
                TemplateVariable(
                    name="expansion_type",
                    description="Type of creative expansion",
                    required=False,
                    default_value="innovative and insightful"
                ),
                TemplateVariable(
                    name="expansion_factor",
                    description="How much to expand the content",
                    required=False,
                    default_value="50-100%"
                ),
                TemplateVariable(
                    name="creative_focus",
                    description="Area to focus creative expansion",
                    required=False,
                    default_value="practical applications and real-world examples"
                )
            ],
            tags=["generation", "creativity", "expansion", "development"],
            author="Selene System"
        )
    ])
    
    return templates


def register_builtin_templates(manager) -> int:
    """
    Register all built-in templates with a template manager.
    
    Args:
        manager: PromptTemplateManager instance
        
    Returns:
        Number of templates registered
    """
    templates = get_builtin_templates()
    registered_count = 0
    
    for template in templates:
        # Check if template with same name already exists
        existing = manager.get_template_by_name(template.name)
        if existing:
            continue
        
        # Save the template directly (bypassing create_template validation)
        if manager._save_template(template):
            manager._templates[template.id] = template
            registered_count += 1
    
    return registered_count


def get_template_for_task(task: str) -> str:
    """
    Get the default template name for a given task.
    
    Args:
        task: Task name ("summarize", "enhance", "extract_insights", "questions", "classify")
        
    Returns:
        Default template name for the task
    """
    task_templates = {
        "summarize": "Basic Summary",
        "enhance": "Content Enhancement", 
        "extract_insights": "Insight Extraction",
        "questions": "Question Generation",
        "classify": "Content Classification",
        "extract_actions": "Action Item Extraction",
        "expand": "Creative Expansion"
    }
    
    return task_templates.get(task, "Basic Summary")