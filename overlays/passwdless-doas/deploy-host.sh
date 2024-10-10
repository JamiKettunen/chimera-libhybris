#!/bin/bash

# hybris as passwordless doas user
$SUDO tee -a "$WORKDIR/etc/doas.conf" >/dev/null <<'EOF'

# Give hybris user root access without requiring a password.
permit nopass hybris
EOF
