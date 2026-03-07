#![forbid(unsafe_code)]

pub fn add(left: u64, right: u64) -> u64 {
    left + right
}

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn adds_values() {
        assert_eq!(add(2, 2), 4);
    }
}
