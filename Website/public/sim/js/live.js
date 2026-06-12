// Live Sim — Supabase Realtime subscriber.
// Reads ?code=XXXXXX from the URL, connects to the broadcast channel,
// and calls onShotReceived(metrics) for each incoming shot.

const SUPABASE_URL     = 'https://aoxturoezgecwceudeef.supabase.co';
const SUPABASE_ANON    = 'sb_publishable_Qk0gdBkqnTb2PV2bEfW-3A_COWs5lOU';

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

let _channel = null;
let _client  = null;

/** Returns the 6-digit code from the URL query string, or null. */
export function getLiveCode() {
  return new URLSearchParams(location.search).get('code') || null;
}

/**
 * Connect to the broadcast channel for the given 6-digit code.
 * @param {string} code
 * @param {(metrics: object) => void} onShotReceived
 * @param {(status: string) => void} onStatusChange  – 'connecting' | 'connected' | 'error'
 */
export function connectLive(code, onShotReceived, onStatusChange) {
  if (_channel) {
    _channel.unsubscribe();
    _channel = null;
  }

  if (!_client) {
    _client = createClient(SUPABASE_URL, SUPABASE_ANON);
  }

  onStatusChange('connecting');

  _channel = _client
    .channel(`tc-sim-${code}`)
    .on('broadcast', { event: 'shot' }, ({ payload }) => {
      onShotReceived(payload);
    })
    .subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        onStatusChange('connected');
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        onStatusChange('error');
      }
    });
}

export function disconnectLive() {
  if (_channel) {
    _channel.unsubscribe();
    _channel = null;
  }
}
