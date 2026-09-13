FROM vllm/vllm-openai:qwen38-flash-next

COPY patch_ple_fp8_selector.py /tmp/patch_ple_fp8_selector.py
RUN python3 /tmp/patch_ple_fp8_selector.py && rm /tmp/patch_ple_fp8_selector.py