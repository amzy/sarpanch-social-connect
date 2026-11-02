import { META_GRAPH_VERSION } from './config';

export interface PublishResult {
  facebook?: { ok: boolean; id?: string; error?: string };
  instagram?: { ok: boolean; id?: string; error?: string };
  x?: { ok: boolean; id?: string; error?: string };
}

async function readError(response: Response): Promise<string> {
  const body = await response.text();
  return `${response.status}: ${body.slice(0, 500)}`;
}

export async function publishFacebook(
  caption: string,
  imageUrl: string,
  pageId: string,
  pageToken: string,
): Promise<{ id: string }> {
  const hasImage = imageUrl.trim().length > 0;
  const endpoint = `https://graph.facebook.com/${META_GRAPH_VERSION.value()}/${encodeURIComponent(pageId)}/${hasImage ? 'photos' : 'feed'}`;
  const body = new URLSearchParams({
    ...(hasImage ? { url: imageUrl, caption } : { message: caption }),
    access_token: pageToken,
  });
  const response = await fetch(endpoint, { method: 'POST', body });
  if (!response.ok) throw new Error(await readError(response));
  const data = await response.json() as { id?: string; post_id?: string };
  if (!data.id && !data.post_id) throw new Error('Meta returned no published photo ID');
  return { id: data.post_id ?? data.id! };
}

export async function publishInstagram(
  caption: string,
  imageUrl: string,
  instagramId: string,
  accessToken: string,
): Promise<{ id: string }> {
  const base = `https://graph.facebook.com/${META_GRAPH_VERSION.value()}`;
  const create = await fetch(`${base}/${encodeURIComponent(instagramId)}/media`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ image_url: imageUrl, caption, access_token: accessToken }),
  });
  if (!create.ok) throw new Error(`Instagram container: ${await readError(create)}`);
  const container = await create.json() as { id?: string };
  if (!container.id) throw new Error('Instagram returned no media container ID');
  const publish = await fetch(`${base}/${encodeURIComponent(instagramId)}/media_publish`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ creation_id: container.id, access_token: accessToken }),
  });
  if (!publish.ok) throw new Error(`Instagram publish: ${await readError(publish)}`);
  const result = await publish.json() as { id?: string };
  if (!result.id) throw new Error('Instagram returned no published media ID');
  return { id: result.id };
}

export async function publishX(caption: string, bearerToken: string): Promise<{ id: string }> {
  const response = await fetch('https://api.x.com/2/tweets', {
    method: 'POST',
    headers: { authorization: `Bearer ${bearerToken}`, 'content-type': 'application/json' },
    body: JSON.stringify({ text: caption }),
  });
  if (!response.ok) throw new Error(await readError(response));
  const result = await response.json() as { data?: { id?: string } };
  if (!result.data?.id) throw new Error('X returned no post ID');
  return { id: result.data.id };
}
