import { esc, layout, renderNote, renderError } from './pkm-render';

describe('esc', () => {
  it('escapes HTML metacharacters in a fixed order', () => {
    expect(esc('<script>"&\'')).toBe('&lt;script&gt;&quot;&amp;&#39;');
  });
  it('treats null/undefined as empty', () => {
    expect(esc(null)).toBe('');
    expect(esc(undefined)).toBe('');
  });
});

describe('layout', () => {
  it('emits a full HTML document with title, viewport, and dark-mode support', () => {
    const html = layout('My Page', '<p>hi</p>');
    expect(html).toContain('<!DOCTYPE html>');
    expect(html).toContain('<title>My Page</title>');
    expect(html).toContain('name="viewport"');
    expect(html).toContain('prefers-color-scheme: dark');
    expect(html).toContain('<p>hi</p>');
  });
  it('escapes the page title', () => {
    expect(layout('<x>', '')).toContain('<title>&lt;x&gt;</title>');
  });
});

describe('renderNote', () => {
  it('escapes user-controlled fields — no raw script injection', () => {
    const html = renderNote({
      id: 1,
      title: '<script>alert(1)</script>',
      content: 'plain body',
      essence: 'an essence',
      concepts: ['<b>x</b>', 'focus'],
      category: 'Health & Body',
      primary_theme: 'theme',
    });
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
    expect(html).toContain('Health &amp; Body'); // & escaped
  });
});

describe('renderError', () => {
  it('renders the message inside a full page', () => {
    const html = renderError('Note not found');
    expect(html).toContain('<!DOCTYPE html>');
    expect(html).toContain('Note not found');
  });
});
