create table hosts (
       mac	     unsigned bigint not null unique,
       datapath_id   unsigned bigint not null,
       port	     unsigned smallint not null,
       is_occupied   unsigned smallint not null
);
