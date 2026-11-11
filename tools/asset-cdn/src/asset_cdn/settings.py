from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration; deployment values come from the environment, never from source."""

    model_config = SettingsConfigDict(env_prefix="ASSET_CDN_")

    bucket: str = Field(min_length=3, description="Private asset bucket name.")
    base_url: str = Field(pattern=r"^https://[^/]+$", description="HTTPS origin of the connector.")
    rclone: str = "rclone"
