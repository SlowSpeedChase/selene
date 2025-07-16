"""
Search tools for SELENE chatbot agent.
These tools provide different search capabilities for finding content in vaults.
"""

import re
from pathlib import Path
from typing import List, Optional

from loguru import logger

from ...vector.chroma_store import ChromaStore
from .base import BaseTool, ToolParameter, ToolResult, ToolStatus


class SearchNotesTool(BaseTool):
    """Tool for text-based search through notes."""
    
    def __init__(self, vault_path: Optional[Path] = None):
        super().__init__()
        self.vault_path = vault_path
        
    @property
    def name(self) -> str:
        return "search_notes"
        
    @property
    def description(self) -> str:
        return "Search for text content within notes using keywords or regex patterns"
        
    @property
    def parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="query",
                type="string",
                description="Search query (keywords or regex pattern)",
                required=True
            ),
            ToolParameter(
                name="case_sensitive",
                type="bool",
                description="Whether search should be case sensitive",
                required=False,
                default=False
            ),
            ToolParameter(
                name="regex",
                type="bool",
                description="Whether to treat query as regex pattern",
                required=False,
                default=False
            ),
            ToolParameter(
                name="max_results",
                type="int",
                description="Maximum number of results to return",
                required=False,
                default=10
            )
        ]
        
    async def execute(self, **kwargs) -> ToolResult:
        query = kwargs.get("query")
        case_sensitive = kwargs.get("case_sensitive", False)
        use_regex = kwargs.get("regex", False)
        max_results = kwargs.get("max_results", 10)
        
        if not self.vault_path:
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message="No vault configured"
            )
            
        try:
            results = []
            flags = 0 if case_sensitive else re.IGNORECASE
            
            # Compile regex pattern
            if use_regex:
                pattern = re.compile(query, flags)
            else:
                # Escape special regex characters for literal search
                escaped_query = re.escape(query)
                pattern = re.compile(escaped_query, flags)
                
            # Search through all markdown files
            for md_file in self.vault_path.glob("**/*.md"):
                if not md_file.is_file():
                    continue
                    
                try:
                    with open(md_file, 'r', encoding='utf-8') as f:
                        content = f.read()
                        
                    # Find matches
                    matches = list(pattern.finditer(content))
                    if matches:
                        # Get context around matches
                        file_results = []
                        for match in matches[:3]:  # Limit matches per file
                            start = max(0, match.start() - 50)
                            end = min(len(content), match.end() + 50)
                            context = content[start:end].replace('\n', ' ')
                            
                            file_results.append({
                                "match_text": match.group(),
                                "context": context,
                                "position": match.start()
                            })
                            
                        relative_path = md_file.relative_to(self.vault_path)
                        results.append({
                            "file_path": str(relative_path),
                            "matches": file_results,
                            "total_matches": len(matches)
                        })
                        
                except Exception as e:
                    logger.warning(f"Error reading file {md_file}: {e}")
                    continue
                    
            # Sort by number of matches
            results.sort(key=lambda x: x["total_matches"], reverse=True)
            results = results[:max_results]
            
            # Format output
            if not results:
                content = f"No matches found for: {query}"
            else:
                content = []
                for result in results:
                    content.append(f"📄 {result['file_path']} ({result['total_matches']} matches)")
                    for match in result['matches']:
                        content.append(f"   💡 {match['context']}")
                        
            return ToolResult(
                status=ToolStatus.SUCCESS,
                content=content,
                metadata={
                    "query": query,
                    "total_files_searched": len(list(self.vault_path.glob("**/*.md"))),
                    "files_with_matches": len(results),
                    "case_sensitive": case_sensitive,
                    "regex_used": use_regex
                }
            )
            
        except Exception as e:
            logger.error(f"Error searching notes: {e}")
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Search failed: {e}"
            )


class VectorSearchTool(BaseTool):
    """Tool for semantic search using vector embeddings."""
    
    def __init__(self):
        super().__init__()
        self.chroma_store = None
        
    @property
    def name(self) -> str:
        return "vector_search"
        
    @property
    def description(self) -> str:
        return "Perform semantic search across notes using AI embeddings"
        
    @property
    def parameters(self) -> List[ToolParameter]:
        return [
            ToolParameter(
                name="query",
                type="string",
                description="Natural language search query",
                required=True
            ),
            ToolParameter(
                name="results",
                type="int",
                description="Number of results to return",
                required=False,
                default=5
            ),
            ToolParameter(
                name="min_similarity",
                type="float",
                description="Minimum similarity score (0.0 to 1.0)",
                required=False,
                default=0.0
            )
        ]
        
    async def execute(self, **kwargs) -> ToolResult:
        query = kwargs.get("query")
        num_results = kwargs.get("results", 5)
        min_similarity = kwargs.get("min_similarity", 0.0)
        
        try:
            # Initialize ChromaDB store if needed
            if not self.chroma_store:
                self.chroma_store = ChromaStore()
                
            # Perform vector search
            search_results = await self.chroma_store.search_similar(
                query=query,
                limit=num_results
            )
            
            if not search_results:
                return ToolResult(
                    status=ToolStatus.SUCCESS,
                    content="No similar documents found",
                    metadata={"query": query, "results_count": 0}
                )
                
            # Filter by similarity threshold
            filtered_results = [
                result for result in search_results 
                if result.get("score", 0) >= min_similarity
            ]
            
            # Format results
            content = []
            for i, result in enumerate(filtered_results, 1):
                score = result.get("score", 0)
                doc_id = result.get("id", "unknown")
                text = result.get("text", "")[:200] + "..." if len(result.get("text", "")) > 200 else result.get("text", "")
                metadata = result.get("metadata", {})
                
                source = metadata.get("source", "Unknown source")
                content.append(f"{i}. 📄 {source} (similarity: {score:.3f})")
                content.append(f"   {text}")
                
            return ToolResult(
                status=ToolStatus.SUCCESS,
                content=content,
                metadata={
                    "query": query,
                    "total_results": len(search_results),
                    "filtered_results": len(filtered_results),
                    "min_similarity": min_similarity
                }
            )
            
        except Exception as e:
            logger.error(f"Vector search failed: {e}")
            return ToolResult(
                status=ToolStatus.ERROR,
                error_message=f"Vector search failed: {e}"
            )