FROM ubuntu:latest

LABEL org.opencontainers.image.authors="mevljas"

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ipmitool \
	&& rm -rf /var/lib/apt/lists/*

COPY functions.sh /app/functions.sh
COPY constants.sh /app/constants.sh
COPY healthcheck.sh /app/healthcheck.sh
COPY Dell_iDRAC_fan_controller.sh /app/Dell_iDRAC_fan_controller.sh

RUN chmod 0755 /app/functions.sh /app/healthcheck.sh /app/Dell_iDRAC_fan_controller.sh \
	&& chmod 0644 /app/constants.sh

WORKDIR /app

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "/app/healthcheck.sh" ]

# you should override these default values when running. See README.md
# ENV IDRAC_HOST=192.168.1.100
ENV IDRAC_HOST=local
# ENV IDRAC_USERNAME=root
# ENV IDRAC_PASSWORD=calvin
# FAN_SPEED is the minimum fan speed used by the temperature curve (0-100).
ENV FAN_SPEED=1
ENV CPU_TEMPERATURE_THRESHOLD=70
ENV CHECK_INTERVAL=60
ENV DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE=false
ENV KEEP_THIRD_PARTY_PCIE_CARD_COOLING_RESPONSE_STATE_ON_EXIT=false

ENTRYPOINT ["./Dell_iDRAC_fan_controller.sh"]
