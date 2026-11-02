import { KeyManagementServiceClient } from '@google-cloud/kms';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { KMS_KEY_NAME, FUNCTION_REGION } from './config';

const kms = new KeyManagementServiceClient();
const db = getFirestore();

async function encrypt(value: string): Promise<string> {
  const [result] = await kms.encrypt({ name: KMS_KEY_NAME.value(), plaintext: Buffer.from(value) });
  if (!result.ciphertext) throw new Error('KMS encryption returned no ciphertext');
  return Buffer.from(result.ciphertext as Uint8Array).toString('base64');
}

export const saveSocialCredentials = onCall({ region: FUNCTION_REGION, secrets: [KMS_KEY_NAME] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const input = request.data as Record<string, unknown>;
  const allowed = ['facebookPageToken', 'instagramId', 'twitterToken', 'facebookPageId'];
  if (Object.keys(input).some((key) => !allowed.includes(key))) {
    throw new HttpsError('invalid-argument', 'Unsupported credential field.');
  }
  const encrypted: Record<string, string> = {};
  for (const key of allowed) {
    const value = input[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      encrypted[key] = ['instagramId', 'facebookPageId'].includes(key) ? value.trim() : await encrypt(value.trim());
    }
  }
  await db.doc(`users/${request.auth.uid}/private/socialTokens`).set({
    ...encrypted,
    updatedAt: new Date(),
  }, { merge: true });
  return { saved: true };
});

export async function readSocialCredentials(uid: string): Promise<Record<string, string>> {
  const snapshot = await db.doc(`users/${uid}/private/socialTokens`).get();
  const stored = snapshot.data() ?? {};
  const result: Record<string, string> = {};
  for (const key of ['facebookPageToken', 'twitterToken']) {
    const value = stored[key];
    if (typeof value !== 'string' || !value) continue;
    const [decrypted] = await kms.decrypt({ name: KMS_KEY_NAME.value(), ciphertext: Buffer.from(value, 'base64') });
    if (decrypted.plaintext) result[key] = Buffer.from(decrypted.plaintext as Uint8Array).toString('utf8');
  }
  if (typeof stored.instagramId === 'string') result.instagramId = stored.instagramId;
  if (typeof stored.facebookPageId === 'string') result.facebookPageId = stored.facebookPageId;
  return result;
}
