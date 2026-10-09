# Jobs contract — synthetic fixture, revision 2
Source ID: JOBS-AC-2; scope: POST /jobs in isolated tenant.
Authorized writer with same tenant, idempotency key and payload gets same job_id on retry; durable job count and outbox effect count both equal one, including concurrent submissions and retry after lost response.
Same key with different payload returns conflict without a second job/effect.
Authorization precedes cached-result lookup: a revoked writer must not retrieve the cached result; a key in another tenant must not expose its result. Failure code text is not fixed here.
Change: new cache lookup and authorization order; no failed logs are supplied.
