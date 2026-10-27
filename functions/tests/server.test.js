const { app } = require('../lib/server');

describe('Bhromon Games Express Server', () => {
  let server;
  let baseUrl;

  beforeAll((done) => {
    server = app.listen(0, () => {
      const port = server.address().port;
      baseUrl = `http://127.0.0.1:${port}`;
      done();
    });
  });

  afterAll((done) => {
    if (server) {
      server.close(done);
    } else {
      done();
    }
  });

  test('GET /health returns healthy status and callable list', async () => {
    const res = await fetch(`${baseUrl}/health`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe('ok');
    expect(body.service).toBe('bhromon-games-server');
    expect(body.callables).toContain('card29Start');
    expect(body.callables).toContain('card29Act');
    expect(body.callables).toContain('card29Advance');
    expect(body.callables).toContain('card29Leave');
    expect(body.callables).toContain('teenPattiStart');
    expect(body.callables).toContain('teenPattiAct');
    expect(body.callables).toContain('teenPattiAdvance');
    expect(body.callables).toContain('teenPattiLeave');
  });

  test('POST /unknown returns 404', async () => {
    const res = await fetch(`${baseUrl}/unknown`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.error.status).toBe('NOT_FOUND');
  });

  test('POST /card29Start without auth header returns 401', async () => {
    const res = await fetch(`${baseUrl}/card29Start`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tourId: 't1', gameId: 'g1' }),
    });
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error.status).toBe('UNAUTHENTICATED');
  });
});
