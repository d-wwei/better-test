# Existing test-groups slice — synthetic, revision 1
J-01: writer submits once, asserts 201 and nonempty job_id.
J-02: writer retries sequentially with identical key; checks only equal response job_id.
Both historical tests green. Durable/outbox observer, concurrent runner and isolated fixture are absent from this input.
