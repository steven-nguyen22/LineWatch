-- Rename subscription_status to subscription_tier and update default
ALTER TABLE profiles RENAME COLUMN subscription_status TO subscription_tier;
ALTER TABLE profiles ALTER COLUMN subscription_tier SET DEFAULT 'rookie';

-- Update existing 'free' values to 'rookie'
UPDATE profiles SET subscription_tier = 'rookie' WHERE subscription_tier = 'free';

-- Add check constraint for valid tier values
ALTER TABLE profiles ADD CONSTRAINT valid_subscription_tier
    CHECK (subscription_tier IN ('rookie', 'pro', 'hall_of_fame'));
