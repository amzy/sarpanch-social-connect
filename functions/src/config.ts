import { defineSecret, defineString } from 'firebase-functions/params';

export const GEMINI_API_KEY = defineSecret('GEMINI_API_KEY');
export const KMS_KEY_NAME = defineSecret('KMS_KEY_NAME');
export const META_GRAPH_VERSION = defineString('META_GRAPH_VERSION');
export const FUNCTION_REGION = 'asia-south1';
