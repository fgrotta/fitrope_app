const test = require('node:test');
const assert = require('node:assert/strict');

const { isoForItalianToday } = require('./seed_today');

test('converte le 09:00 italiane con ora solare', () => {
  const winter = new Date('2026-12-15T12:00:00Z');
  assert.equal(isoForItalianToday(9, winter), '2026-12-15T08:00:00Z');
});

test('converte le 09:00 italiane con ora legale', () => {
  const summer = new Date('2026-08-15T12:00:00Z');
  assert.equal(isoForItalianToday(9, summer), '2026-08-15T07:00:00Z');
});

test('usa il giorno italiano quando in UTC è ancora il precedente', () => {
  // 22:30Z del 25 agosto sono le 00:30 italiane del 26 agosto.
  const afterItalianMidnight = new Date('2026-08-25T22:30:00Z');
  assert.equal(
    isoForItalianToday(9, afterItalianMidnight),
    '2026-08-26T07:00:00Z',
  );
});
