import { randomUUID } from 'node:crypto';
import { GoogleGenAI } from '@google/genai';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { GEMINI_API_KEY, KMS_KEY_NAME, FUNCTION_REGION } from './config';
import { claimAiGeneration, hasActivePremium } from './billing';
import { readSocialCredentials, saveSocialCredentials as saveSocialCredentialsHandler } from './credentials';
import { publishFacebook, publishInstagram, publishX, PublishResult } from './social';

initializeApp();
setGlobalOptions({ region: FUNCTION_REGION, maxInstances: 10 });
const db = getFirestore();

const languages = new Set(['English', 'Hindi', 'Marathi', 'Telugu', 'Tamil', 'Gujarati']);

export const generatePostCaption = onDocumentCreated({
  document: 'posts_queue/{postId}',
  secrets: [GEMINI_API_KEY],
  retry: true,
}, async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const post = snapshot.data();
  if (post.status !== 'pending_ai') return;
  const uid = String(post.uid ?? '');
  if (!uid) {
    await snapshot.ref.update({ status: 'failed', failureCode: 'MISSING_UID' });
    return;
  }
  const userSnapshot = await db.doc(`users/${uid}`).get();
  const user = userSnapshot.data() ?? {};
  const language = String(post.contentLanguage ?? user.primaryLanguage ?? 'Hindi');
  if (!languages.has(language)) {
    await snapshot.ref.update({ status: 'failed', failureCode: 'UNSUPPORTED_LANGUAGE' });
    return;
  }
  const claim = await claimAiGeneration(uid, snapshot.ref);
  if (!claim.allowed) {
    await snapshot.ref.update({
      status: 'failed', failureCode: claim.reason ?? 'USAGE_DENIED',
      failedAt: FieldValue.serverTimestamp(),
      aiProcessingLeaseUntil: FieldValue.delete(),
    });
    return;
  }
  if (claim.shouldProcess === false) return;

  try {
    const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
    const type = String(post.type ?? 'development');
    const rawNotes = String(post.rawNotes ?? '').trim();
    const prompt = [
      'Act as a professional public relations writer for an Indian village Gram Panchayat Sarpanch.',
      'Write an impactful, humble, factual public update. Do not invent achievements, budgets, dates, names, statistics, approvals or promises.',
      `Write entirely in ${language}. Preserve proper nouns and numbers supplied by the user.`,
      'Use a respectful, accessible tone suitable for village residents. Avoid partisan attacks, inflammatory language, requests for votes, or unsupported political claims.',
      `Post type: ${type}.`,
      `Sarpanch: ${String(user.sarpanchName ?? '')}. Panchayat: ${String(user.panchayatName ?? '')}. District: ${String(user.district ?? '')}. State: ${String(user.state ?? '')}.`,
      `User notes: ${rawNotes || 'Create a concise festival greeting based only on the selected festival context.'}`,
      'Return only the caption text, with no quotation marks or explanation.',
    ].join('\n');
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents: prompt,
      config: { temperature: 0.55, maxOutputTokens: 700 },
    });
    const caption = response.text?.trim();
    if (!caption) throw new Error('Gemini returned an empty caption');
    await snapshot.ref.update({
      aiCaption: caption,
      status: 'pending_approval',
      aiGeneratedAt: FieldValue.serverTimestamp(),
      aiLanguage: language,
      aiProcessingLeaseUntil: FieldValue.delete(),
      failureCode: FieldValue.delete(),
    });
  } catch (error) {
    logger.error('Caption generation failed', { postId: event.params.postId, error });
    await snapshot.ref.update({
      status: 'failed', failureCode: 'AI_GENERATION_FAILED',
      failureMessage: error instanceof Error ? error.message.slice(0, 500) : 'Unknown error',
      failedAt: FieldValue.serverTimestamp(),
      aiProcessingLeaseUntil: FieldValue.delete(),
    });
  }
});

export const dispatchApprovedPost = onDocumentUpdated({
  document: 'posts_queue/{postId}',
  secrets: [KMS_KEY_NAME],
  retry: true,
}, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  const postRef = event.data?.after.ref;
  if (!before || !after || !postRef) return;
  if (before.status === 'approved_to_publish' || after.status !== 'approved_to_publish') return;
  const uid = String(after.uid ?? '');
  if (!uid) return postRef.update({ status: 'failed', failureCode: 'MISSING_UID' });
  if (!(await hasActivePremium(uid))) {
    return postRef.update({ status: 'failed', failureCode: 'PREMIUM_REQUIRED_FOR_AUTOPUBLISH' });
  }

  const claim = await db.runTransaction(async (transaction) => {
    const current = await transaction.get(postRef);
    if (!current.exists || current.data()?.status !== 'approved_to_publish') return false;
    const currentData = current.data() ?? {};
    const lease = currentData.publishLeaseUntil as Timestamp | undefined;
    if (currentData.publishClaimed === true && lease && lease.toMillis() > Date.now()) return false;
    transaction.update(postRef, {
      publishClaimed: true,
      publishLeaseUntil: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
      publishStartedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!claim) return;

  try {
    const userSnapshot = await db.doc(`users/${uid}`).get();
    const user = userSnapshot.data() ?? {};
    const credentials = await readSocialCredentials(uid);
    const caption = String(after.aiCaption ?? '').trim();
    const imageUrl = String(after.finalCompositedImage ?? '').trim();
    const results: PublishResult = {};
    const attempts: Promise<void>[] = [];

    if (credentials.facebookPageToken && credentials.facebookPageId && imageUrl) {
      attempts.push(publishFacebook(caption, imageUrl, credentials.facebookPageId, credentials.facebookPageToken)
        .then((value) => { results.facebook = { ok: true, id: value.id }; })
        .catch((error: unknown) => { results.facebook = { ok: false, error: String(error).slice(0, 500) }; }));
    }
    if (credentials.facebookPageToken && credentials.instagramId && imageUrl) {
      attempts.push(publishInstagram(caption, imageUrl, credentials.instagramId, credentials.facebookPageToken)
        .then((value) => { results.instagram = { ok: true, id: value.id }; })
        .catch((error: unknown) => { results.instagram = { ok: false, error: String(error).slice(0, 500) }; }));
    }
    if (credentials.twitterToken) {
      attempts.push(publishX(caption, credentials.twitterToken)
        .then((value) => { results.x = { ok: true, id: value.id }; })
        .catch((error: unknown) => { results.x = { ok: false, error: String(error).slice(0, 500) }; }));
    }
    await Promise.all(attempts);
    const successes = Object.values(results).filter((result) => result?.ok).length;
    const failures = Object.values(results).filter((result) => !result?.ok).length;
    const finalStatus = successes > 0 ? 'published' : 'failed';
    await postRef.update({
      status: finalStatus,
      publishResults: results,
      publishedAt: successes > 0 ? FieldValue.serverTimestamp() : FieldValue.delete(),
      failureCode: successes === 0 ? (failures > 0 ? 'ALL_CHANNELS_FAILED' : 'NO_CHANNELS_CONFIGURED') : FieldValue.delete(),
      publishCompletedAt: FieldValue.serverTimestamp(),
      publishLeaseUntil: FieldValue.delete(),
      publisherDisplayName: String(user.sarpanchName ?? ''),
    });
  } catch (error) {
    logger.error('Social publishing dispatch failed', { postId: event.params.postId, error });
    await postRef.update({
      status: 'failed',
      failureCode: 'PUBLISH_DISPATCH_FAILED',
      failureMessage: error instanceof Error ? error.message.slice(0, 500) : 'Unknown error',
      publishCompletedAt: FieldValue.serverTimestamp(),
      publishLeaseUntil: FieldValue.delete(),
    });
  }
});

export const saveSocialCredentials = saveSocialCredentialsHandler;

export const retryFailedPost = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const postId = String((request.data as { postId?: unknown }).postId ?? '');
  if (!postId) throw new HttpsError('invalid-argument', 'postId is required.');
  const ref = db.doc(`posts_queue/${postId}`);
  const snapshot = await ref.get();
  if (!snapshot.exists || snapshot.data()?.uid !== request.auth.uid) {
    throw new HttpsError('not-found', 'Post not found.');
  }
  if (snapshot.data()?.status !== 'failed') {
    throw new HttpsError('failed-precondition', 'Only failed posts can be retried.');
  }
  const previous = snapshot.data() ?? {};
  const nextPostId = randomUUID();
  const aiRetry = ['AI_GENERATION_FAILED', 'FREE_MONTHLY_LIMIT_REACHED', 'BILLING_INACTIVE', 'USAGE_DENIED', 'USER_PROFILE_MISSING', 'UNSUPPORTED_LANGUAGE'].includes(String(previous.failureCode ?? ''));
  const retryPayload: Record<string, unknown> = {
    postId: nextPostId,
    uid: request.auth.uid,
    type: String(previous.type ?? 'development'),
    contentLanguage: String(previous.contentLanguage ?? 'Hindi'),
    creationTimestamp: FieldValue.serverTimestamp(),
    rawNotes: String(previous.rawNotes ?? ''),
    beforeImageUrl: String(previous.beforeImageUrl ?? ''),
    afterImageUrl: String(previous.afterImageUrl ?? ''),
    finalCompositedImage: String(previous.finalCompositedImage ?? ''),
    status: aiRetry ? 'pending_ai' : 'pending_approval',
    scheduledTime: previous.scheduledTime ?? null,
  };
  if (!aiRetry) retryPayload.aiCaption = String(previous.aiCaption ?? '');
  await db.doc(`posts_queue/${nextPostId}`).create(retryPayload);
  return { queued: true, postId: nextPostId, status: aiRetry ? 'pending_ai' : 'pending_approval' };
});

/**
 * One-time development administrator bootstrap.
 * Access is granted only to the explicitly verified development phone number.
 */
export const bootstrapDevelopmentAdmin = onCall({ region: FUNCTION_REGION }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in with your verified phone number first.');
  const verifiedPhone = String(request.auth.token.phone_number ?? '');
  if (verifiedPhone !== '+91900165600') {
    throw new HttpsError('permission-denied', 'This account is not on the development administrator allowlist.');
  }

  const existingClaims = request.auth.token;
  if (existingClaims.admin === true && existingClaims.developmentAdmin === true) {
    return { isAdmin: true, alreadyConfigured: true };
  }

  await getAuth().setCustomUserClaims(request.auth.uid, {
    admin: true,
    developmentAdmin: true,
  });

  return { isAdmin: true, alreadyConfigured: false };
});
