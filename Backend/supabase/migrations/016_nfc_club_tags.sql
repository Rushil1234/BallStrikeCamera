-- Add NFC tag ID to clubs so each physical NFC sticker maps to one club
ALTER TABLE clubs ADD COLUMN IF NOT EXISTS nfc_tag_id text UNIQUE;

-- NFC shot log: every time a user taps a club NFC tag during a round
CREATE TABLE IF NOT EXISTS nfc_shots (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    round_id    uuid,           -- NULL until round is associated
    club_id     uuid,           -- the club that was tapped
    hole_number int,
    latitude    double precision,
    longitude   double precision,
    tapped_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS nfc_shots_user_idx  ON nfc_shots(user_id);
CREATE INDEX IF NOT EXISTS nfc_shots_round_idx ON nfc_shots(round_id);

-- RLS
ALTER TABLE nfc_shots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users own their nfc_shots" ON nfc_shots
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
