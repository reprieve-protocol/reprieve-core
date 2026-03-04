require('dotenv').config();
const { Client } = require('pg');

(async () => {
  const client = new Client({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    ssl:
      String(process.env.DB_SSL || '').toLowerCase() === 'true'
        ? { rejectUnauthorized: false }
        : false,
  });

  await client.connect();

  const jobs = await client.query(
    `SELECT id, message_id, status, attempt_count, next_attempt_at, last_error, source_chain_id, destination_chain_id, updated_at
       FROM relay_jobs
      ORDER BY updated_at DESC
      LIMIT 20`
  );

  const unresolved = await client.query(
    `SELECT LOWER(ci.message_id) AS message_id,
            LOWER(ci.exec_id) AS exec_id,
            ci.chain_id AS source_chain_id
       FROM rescue_events ci
      WHERE ci.event_name = 'CrossChainInitiated'
        AND ci.message_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
            FROM rescue_events t
           WHERE LOWER(t.message_id) = LOWER(ci.message_id)
             AND t.event_name IN ('CrossChainCompleted','CrossChainDestinationFailed','MessageFailed')
        )
      ORDER BY ci.id DESC
      LIMIT 20`
  );

  console.log('relay_jobs:', JSON.stringify(jobs.rows, null, 2));
  console.log('unresolved_cross_chain:', JSON.stringify(unresolved.rows, null, 2));

  await client.end();
})();
