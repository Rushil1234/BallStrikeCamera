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
 * @param {() => void} [onPing]         – called when app taps "Connect"
 * @param {(name: string) => void} [onClubChanged] – called when app changes club
 */
const _seenSeqs = new Set();
let _ackSupported = true;

async function _ackShot(code, seq) {
  if (!_ackSupported || !_client) return;
  try {
    const { error } = await _client
      .from('live_sim_state')
      .upsert({ code, last_ack_seq: seq, updated_at: new Date().toISOString() }, { onConflict: 'code' });
    if (error) _ackSupported = false;   // column not migrated yet
  } catch (_) { /* never block on ack */ }
}

export function connectLive(code, onShotReceived, onStatusChange, onPing, onClubChanged, onSessionEnd, onSwingImage, onPlayersReceived) {
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
      // Delivery guarantees: dedupe resent shots by seq and ack receipt via
      // the state row the phone already polls. Ack is feature-detected so the
      // sim keeps working before the last_ack_seq migration is applied.
      const seq = payload?.seq;
      if (seq != null) {
        if (_seenSeqs.has(seq)) return;
        _seenSeqs.add(seq);
        if (_seenSeqs.size > 300) _seenSeqs.clear();
        _ackShot(code, seq);
      }
      onShotReceived(payload);
    })
    .on('broadcast', { event: 'ping' }, () => {
      if (onPing) onPing();
    })
    .on('broadcast', { event: 'club' }, ({ payload }) => {
      if (onClubChanged && payload?.clubName) onClubChanged(payload.clubName);
    })
    .on('broadcast', { event: 'swing' }, ({ payload }) => {
      if (onSwingImage && payload?.jpegB64) onSwingImage(payload.jpegB64);
    })
    .on('broadcast', { event: 'end' }, () => {
      if (onSessionEnd) onSessionEnd();
    })
    // Multi-player roster: sent once when the phone starts a multi-player session so the
    // sim can track every player's own ball position independently (single-player sessions
    // never send this, so `names` is only ever populated for multi-player rounds).
    .on('broadcast', { event: 'players' }, ({ payload }) => {
      if (onPlayersReceived && Array.isArray(payload?.names)) onPlayersReceived(payload.names);
    })
    .subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        onStatusChange('connected');
      } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        onStatusChange('error');
      }
    });
}

/**
 * Best-effort upsert of the sim's live state (current hole, last shot, score)
 * so a paired phone can poll `live_sim_state` and mirror the sim in near-real-time.
 */
export async function publishLiveState(code, state) {
  if (!code) return;
  if (!_client) _client = createClient(SUPABASE_URL, SUPABASE_ANON);
  try {
    await _client
      .from('live_sim_state')
      .upsert({ code, ...state, updated_at: new Date().toISOString() }, { onConflict: 'code' });
  } catch (_) {
    // never block the game loop on a network hiccup
  }
}

export function disconnectLive() {
  if (_channel) {
    _channel.unsubscribe();
    _channel = null;
  }
}
