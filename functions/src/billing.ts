import { FieldValue, Timestamp, getFirestore, DocumentReference } from 'firebase-admin/firestore';

const db = getFirestore();
const FREE_MONTHLY_AI_LIMIT = 3;

export interface UsageClaim {
  allowed: boolean;
  shouldProcess?: boolean;
  reason?: string;
  plan: string;
  monthKey: string;
}

function currentIndiaMonth(now = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit',
  }).formatToParts(now);
  const year = parts.find((part) => part.type === 'year')?.value ?? '0000';
  const month = parts.find((part) => part.type === 'month')?.value ?? '00';
  return `${year}-${month}`;
}

export async function claimAiGeneration(
  uid: string,
  postRef: DocumentReference,
): Promise<UsageClaim> {
  const userRef = db.doc(`users/${uid}`);
  const monthKey = currentIndiaMonth();
  return db.runTransaction(async (transaction) => {
    const [userSnapshot, postSnapshot] = await Promise.all([
      transaction.get(userRef), transaction.get(postRef),
    ]);
    if (!postSnapshot.exists) return { allowed: false, reason: 'POST_MISSING', plan: 'free', monthKey };
    const post = postSnapshot.data() ?? {};
    if (!userSnapshot.exists) return { allowed: false, reason: 'USER_PROFILE_MISSING', plan: 'free', monthKey };
    if (post.aiUsageClaimed === true) {
      const user = userSnapshot.data() ?? {};
      const lease = post.aiProcessingLeaseUntil as Timestamp | undefined;
      if (lease && lease.toMillis() > Date.now()) {
        return { allowed: true, shouldProcess: false, plan: String(user.plan ?? 'free'), monthKey };
      }
      transaction.update(postRef, {
        aiProcessingLeaseUntil: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
      });
      return { allowed: true, shouldProcess: true, plan: String(user.plan ?? 'free'), monthKey };
    }
    const user = userSnapshot.data() ?? {};
    const plan = String(user.plan ?? 'free').toLowerCase();
    const billingStatus = String(user.billingStatus ?? 'inactive').toLowerCase();
    if (billingStatus !== 'active') return { allowed: false, reason: 'BILLING_INACTIVE', plan, monthKey };
    const usage = (user.usage ?? {}) as Record<string, unknown>;
    const generationUsage = (usage.aiGenerations ?? {}) as Record<string, unknown>;
    const monthCount = Number(generationUsage[monthKey] ?? 0);
    if (plan !== 'premium' && monthCount >= FREE_MONTHLY_AI_LIMIT) {
      return { allowed: false, reason: 'FREE_MONTHLY_LIMIT_REACHED', plan, monthKey };
    }
    transaction.set(userRef, {
      usage: { aiGenerations: { [monthKey]: FieldValue.increment(1) }, lastAiGenerationAt: Timestamp.now() },
    }, { merge: true });
    transaction.update(postRef, {
      aiUsageClaimed: true,
      aiUsageMonth: monthKey,
      aiProcessingLeaseUntil: Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
    });
    return { allowed: true, shouldProcess: true, plan, monthKey };
  });
}

export async function hasActivePremium(uid: string): Promise<boolean> {
  const snapshot = await db.doc(`users/${uid}`).get();
  const data = snapshot.data() ?? {};
  return String(data.plan ?? '').toLowerCase() === 'premium'
    && String(data.billingStatus ?? '').toLowerCase() === 'active';
}
