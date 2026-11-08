-- The API connects as gatelog_app, which is not the table owner and has no BYPASSRLS,
-- so Row-Level Security applies to every query it makes. Migrations run as gatelog_owner.
CREATE ROLE gatelog_app LOGIN PASSWORD 'gatelog_app';
CREATE DATABASE gatelog_test OWNER gatelog_owner;
