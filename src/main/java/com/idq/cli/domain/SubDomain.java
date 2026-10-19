package com.idq.cli.domain;

/// Member sub-domains; a target table belongs to exactly one.
public enum SubDomain {
    DEMOGRAPHICS("Demographics"),
    PHONE_EMAIL("Phone-email"),
    ADDRESS("Address"),
    ALTERNATE_ID("Alternate-ID"),
    ALTERNATE_NAME("Alternate-Name"),
    PARTY_MANAGED_ATTRIB("Party-Managed-Attrib"),
    ROLE("Role");

    public final String label;

    SubDomain(String label) {
        this.label = label;
    }
}
