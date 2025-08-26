"""Data processing utilities for CMS job performance analysis.

This module provides functions to extract and analyze timing data from CMS job log files,
specifically designed to process SONIC (Service-Oriented Neural Inference Computing) 
job output files and create performance metrics DataFrames.
"""

import logging
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import List, Dict, Any, Optional, Union
import warnings

import pandas as pd
import glob

# Configure logging
logger = logging.getLogger(__name__)

# Constants
DEFAULT_BUFFER_SIZE = 8192  # Increased for better performance
TIMING_PHRASE = 'Time Summary:'
LINES_TO_EXTRACT = 19
DEFAULT_THROUGHPUT = '0 ev/s'

# Sections to filter out for cleaner data
FILTERED_SECTIONS = frozenset(['CPU Summary'])
FILTERED_PROCESSING_KEYS = frozenset(['Number of Events'])


class DataProcessingError(Exception):
    """Custom exception for data processing errors."""
    pass


def _validate_file_path(filepath: Union[str, Path]) -> Path:
    """Validate and convert file path to Path object.
    
    Args:
        filepath: File path to validate
        
    Returns:
        Validated Path object
        
    Raises:
        DataProcessingError: If file doesn't exist or isn't readable
    """
    path = Path(filepath)
    if not path.exists():
        raise DataProcessingError(f"File does not exist: {path}")
    if not path.is_file():
        raise DataProcessingError(f"Path is not a file: {path}")
    if not os.access(path, os.R_OK):
        raise DataProcessingError(f"File is not readable: {path}")
    return path


def read_file_reverse(filename: Union[str, Path], phrase: str, 
                     buffer_size: int = DEFAULT_BUFFER_SIZE) -> List[bytes]:
    """Read a file from the end and extract lines after finding a specific phrase.
    
    This function reads a file from the end in chunks, searching for a specific phrase.
    When the phrase is found, it returns the next LINES_TO_EXTRACT lines.
    This is optimized for log files where timing summaries appear near the end.
    
    Args:
        filename: Path to the file to read
        phrase: Text phrase to search for (e.g., 'Time Summary:')
        buffer_size: Size of chunks to read (default: 8192 bytes)
        
    Returns:
        List of byte strings containing the lines after the phrase,
        or empty list if phrase not found
        
    Raises:
        DataProcessingError: If file cannot be read
    """
    try:
        path = _validate_file_path(filename)
        phrase_bytes = phrase.encode('utf-8')
        
        with path.open('rb') as file:
            file.seek(0, 2)  # Move to the end of the file
            file_size = file.tell()
            
            if file_size == 0:
                logger.warning(f"Empty file: {path}")
                return []
            
            data = b""
            position = file_size
            
            while position > 0:
                # Read chunk from file
                chunk_start = max(0, position - buffer_size)
                file.seek(chunk_start)
                chunk = file.read(position - chunk_start)
                data = chunk + data
                position = chunk_start
                
                # Split into lines and search
                lines = data.split(b'\n')
                
                # Search for phrase in reverse order
                for i, line in enumerate(reversed(lines)):
                    if phrase_bytes in line:
                        lines_idx = len(lines) - i
                        # Return found line plus next LINES_TO_EXTRACT lines
                        return lines[lines_idx:lines_idx + LINES_TO_EXTRACT]
                
                # Keep some overlap for phrases that might be split across chunks
                if len(data) > buffer_size * 2:
                    data = data[-buffer_size:]
            
            return []
            
    except (OSError, IOError) as e:
        raise DataProcessingError(f"Error reading file {filename}: {e}") from e


def parse_output_to_dict(output: List[bytes], 
                        encoding: str = 'utf-8') -> Dict[str, str]:
    """Parse CMS job timing output into a structured dictionary.
    
    Parses the timing summary section from CMS job logs, extracting key-value pairs
    for performance metrics like event throughput, processing time, etc.
    Filters out CPU Summary and most Processing Summary fields to focus on 
    relevant timing data.
    
    Args:
        output: List of byte strings containing the timing summary lines
        encoding: Text encoding to use (default: utf-8)
        
    Returns:
        Dictionary mapping metric names to their string values
        
    Raises:
        DataProcessingError: If parsing fails
    """
    if not output:
        return {}
    
    try:
        # Convert bytes to strings efficiently
        lines = [line.decode(encoding, errors='replace').strip() 
                for line in output if line.strip()]
        
        data_dict = {}
        current_section = None
        
        for line in lines:
            if not line:
                continue
                
            if line.endswith(':'):
                # Section header
                current_section = line.rstrip(':').strip()
                continue
            
            if ':' not in line:
                continue
                
            key, value = line.split(':', 1)
            key = key.strip().lstrip('-').strip()
            value = value.strip()
            
            # Apply filters
            if current_section in FILTERED_SECTIONS:
                continue
            if (current_section == "Processing Summary" and 
                key not in FILTERED_PROCESSING_KEYS):
                continue
                
            if key and value:  # Only add non-empty key-value pairs
                data_dict[key] = value
        
        return data_dict
        
    except (UnicodeDecodeError, ValueError) as e:
        raise DataProcessingError(f"Error parsing output data: {e}") from e


def _process_single_file(filepath: str, phrase: str = TIMING_PHRASE) -> Dict[str, Any]:
    """Process a single file and extract timing data.
    
    Args:
        filepath: Path to the file to process
        phrase: Phrase to search for in the file
        
    Returns:
        Dictionary containing timing data and file path
    """
    file_dict = {'file': filepath}
    
    try:
        text_data = read_file_reverse(filepath, phrase)
        if text_data:
            timing_data = parse_output_to_dict(text_data)
            file_dict.update(timing_data)
        else:
            logger.debug(f"No timing data found in {filepath}")
    except DataProcessingError as e:
        logger.warning(f"Error processing {filepath}: {e}")
    
    return file_dict


def get_data_set(folder_path: str, max_workers: Optional[int] = None) -> List[Dict[str, Any]]:
    """Extract timing data from all matching log files in a directory pattern.
    
    Processes all files matching the given glob pattern, extracting timing summary
    data from each file. Uses parallel processing for improved performance.
    Files without timing data are still included but only contain the filename.
    
    Args:
        folder_path: Glob pattern for log files (e.g., '/path/*/job_*.out')
        max_workers: Maximum number of worker threads (default: CPU count)
        
    Returns:
        List of dictionaries, each containing timing metrics and filename.
        Files without timing data only contain the 'file' key.
        
    Raises:
        DataProcessingError: If glob pattern is invalid
    """
    try:
        files = glob.glob(folder_path)
    except (OSError, ValueError) as e:
        raise DataProcessingError(f"Invalid glob pattern '{folder_path}': {e}") from e
    
    if not files:
        logger.warning(f"No files found matching pattern: {folder_path}")
        return []
    
    logger.info(f"Processing {len(files)} files...")
    
    # Use ThreadPoolExecutor for I/O bound operations
    data_set = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all file processing tasks
        future_to_file = {
            executor.submit(_process_single_file, filepath): filepath 
            for filepath in files
        }
        
        # Collect results as they complete
        for future in as_completed(future_to_file):
            try:
                result = future.result()
                data_set.append(result)
            except Exception as e:
                filepath = future_to_file[future]
                logger.error(f"Error processing {filepath}: {e}")
    
    return data_set


def filter_successful_jobs(job_data: List[Dict[str, Any]], 
                          throughput_key: str = 'Event Throughput') -> List[Dict[str, Any]]:
    """Filter out failed jobs that have zero event throughput.
    
    Removes entries from the dataset that don't have valid event throughput data,
    indicating failed or incomplete jobs.
    
    Args:
        job_data: List of dictionaries containing job data
        throughput_key: Key name for throughput data
        
    Returns:
        Filtered list containing only successful jobs with non-zero throughput
    """
    if not job_data:
        return []
    
    return [
        job for job in job_data 
        if job.get(throughput_key, DEFAULT_THROUGHPUT) != DEFAULT_THROUGHPUT
    ]


def get_df_data(folder_name: str, 
                max_workers: Optional[int] = None,
                verbose: bool = True) -> pd.DataFrame:
    """Process CMS job log files and create a performance analysis DataFrame.
    
    Main function that orchestrates the entire data processing pipeline:
    1. Extracts timing data from all matching log files (parallel processing)
    2. Filters out failed jobs
    3. Creates a pandas DataFrame with performance metrics
    4. Adds a numeric 'evt/s' column for analysis
    5. Optionally prints summary statistics
    
    Args:
        folder_name: Glob pattern for log files to process
        max_workers: Maximum number of worker threads for file processing
        verbose: Whether to print summary statistics
        
    Returns:
        DataFrame containing job performance data with columns including:
        - Event Throughput: Original throughput string (e.g., '4.5 ev/s')
        - evt/s: Numeric throughput value for analysis
        - file: Source log file path
        - Additional timing metrics from the log files
        
    Raises:
        DataProcessingError: If processing fails
    """
    try:
        # Extract raw data from all matching files
        logger.info("Starting data extraction...")
        data_set = get_data_set(folder_name, max_workers=max_workers)
        
        if not data_set:
            logger.warning("No data extracted from files")
            return pd.DataFrame()
        
        # Filter to only successful jobs
        successful_jobs = filter_successful_jobs(data_set)
        
        # Calculate statistics
        num_successful = len(successful_jobs)
        num_failed = len(data_set) - num_successful
        
        if verbose:
            print(f'Number of successful jobs {num_successful} - Number of failed {num_failed}')
        
        if num_successful == 0:
            logger.warning("No successful jobs found")
            return pd.DataFrame()
        
        # Create DataFrame
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", category=FutureWarning)
            df = pd.DataFrame(successful_jobs)
        
        # Add numeric throughput column with error handling
        if 'Event Throughput' in df.columns:
            try:
                df['evt/s'] = pd.to_numeric(
                    df['Event Throughput'].str.replace('ev/s', '', regex=False),
                    errors='coerce'
                )
                
                # Remove rows with invalid throughput values
                invalid_mask = df['evt/s'].isna()
                if invalid_mask.any():
                    logger.warning(f"Removing {invalid_mask.sum()} rows with invalid throughput data")
                    df = df[~invalid_mask].copy()
                
                if verbose and not df.empty:
                    avg_throughput = df['evt/s'].mean()
                    print(f"    Average throughput {avg_throughput:.2f} evt/s")
                    
            except Exception as e:
                logger.error(f"Error processing throughput data: {e}")
                raise DataProcessingError(f"Failed to process throughput data: {e}") from e
        else:
            logger.warning("No 'Event Throughput' column found in data")
        
        logger.info(f"Successfully processed {len(df)} jobs")
        return df
        
    except Exception as e:
        if isinstance(e, DataProcessingError):
            raise
        raise DataProcessingError(f"Failed to process data: {e}") from e
