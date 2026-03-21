import { FastifyInstance } from 'fastify';
import { getCrossThreadAssociations } from '../lib/db';

export async function briefingRoutes(server: FastifyInstance) {
  // GET /api/briefing/associations?minSimilarity=0.7&recentDays=7&limit=10
  server.get<{
    Querystring: { minSimilarity?: number; recentDays?: number; limit?: number };
  }>('/api/briefing/associations', async (request) => {
    const {
      minSimilarity = 0.7,
      recentDays = 7,
      limit = 10,
    } = request.query;

    const associations = getCrossThreadAssociations({
      minSimilarity,
      recentDays,
      limit,
    });

    return { count: associations.length, associations };
  });
}
